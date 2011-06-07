/*****************************************************************************
 * Parser for Tcl subset
 *
 * Modifed by Benedikt Schraik, 2011
 * Copyright (C) 2010      by Rene Zaumseil
 * based on the work of Dimitri van Heesch.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation under the terms of the GNU General Public License is hereby
 * granted. No representations are made about the suitability of this software
 * for any purpose. It is provided "as is" without express or implied warranty.
 * See the GNU General Public License for more details.
 *
 * Documents produced by Doxygen are derivative works derived from the
 * input used in their production; they are not affected by this license.
 *
 */
%{
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <ctype.h>
#include <stdint.h>

#include "qtbc.h"
#include <qarray.h>
#include <qstack.h>
#include <qregexp.h>
	//#include <qlist.h>
#include <unistd.h>
#include <qfile.h>
#include <qdict.h>

#include "entry.h"
#include "message.h"
#include "config.h"
#include "doxygen.h"
#include "util.h"
#include "defargs.h"
#include "language.h"
#include "commentscan.h"
#include "pre.h"
#include "tclscanner.h"
#include "outputlist.h"
#include "membername.h"
#include "searchindex.h"
#include "commentcnv.h"
#include "bufstr.h"
#include "portable.h"

#include <stdarg.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qlist.h>

#define YY_NEVER_INTERACTIVE 1

#define MAX_INCLUDE_DEPTH 10


//! Structure containing the current scan context
class tcl_context {
 public:
	int line0; //start of segment
	int line1; //end of segment
	Entry *e_current;
	Entry *e_inside;

	tcl_context() {
		this->line0 = 0;
		this->line1 = 0;
		this->e_current = NULL;
		this->e_inside = NULL;
	}
};

//! Structure containing all internal global variables.
static struct {
	CodeOutputInterface * code; // if set then we are codifying the file
	int code_line; // current line of code
	int code_linenumbers; // if true create line numbers in code

	bool config_autobrief; // value of configuration option
	const char* input_string; // file contents
	int input_position; // position in file
	QCString file_name; // name of used file
	ParserInterface *this_parser; // myself

	//used by Helper Functions
	QCString func_args_temp;
	int func_args_bcnt;
	Argument* a_current;

	QCString func_body_temp;

	Entry* e_main; // top level entry
	Entry* e_current; // currently used entry
	Entry* e_inside; // parent entry

	tcl_context* t_current; // used for creating new context

	QStack<tcl_context> stack; // stack of scan contexts
	QDict<Entry> ns; // all read namespace entries
	QDict<Entry> cl; // all read class entries
	QDict<Entry> fn; // all read function entries
	QList<Entry> entry; // list of all created entries
	Protection protection; // current protections state
 } tcl;
//------------------------------------------------------------
// Global Vars
// used by scanner
enum CMTTYP { NAME, AUTHOR, BRIEF, ARGS, RETURN } ctyp;

//------------------------------------------------------------
// Prototypes
static int yyread(char *buf, int max_size);
void tcl_cmt_store(QCString txt);
void tcl_func_name(QCString txt);
void tcl_func_args(QCString txt, int line);
void tcl_func_body(QCString txt);
void tcl_block_start(int line);
void tcl_block_end(tcl_context* context, int line);
void tcl_class_init(QCString txt, int line);

//-----------------------------------------------------------------------
#undef YY_INPUT
#define YY_INPUT(buf,result,max_size) result=yyread(buf,max_size);
//-----------------------------------------------------------------------
%}

WHITE [ \t]
NONWHITE [^ \t\n]

%option yylineno
%option noyywrap
%option stack
%option debug

/* Start Conditions */
%x QUOTE
%x CMTHEAD
%x FUNCARGS
%x CMTARGS
%x CMTRANGE

%x FUNCBODY

%%
\"			yy_push_state(QUOTE);
<QUOTE>[^\\]\"		yy_pop_state();

#%[A-Za-z]*Header(#)*\n		yy_push_state(CMTHEAD);
#%[A-Za-z]*Range{WHITE}*\n	yy_push_state(CMTRANGE);
#%[A-Za-z]*Args{WHITE}*\n	yy_push_state(CMTARGS);
#[^%].*\n

<CMTHEAD>^[^#]				{ yy_pop_state(); yyless(0); }
<CMTHEAD>^#Name{WHITE}*:.+\n		{ ctyp = NAME; tcl_cmt_store(yytext); }
<CMTHEAD>^#Author{WHITE}*:.+\n		{ ctyp = AUTHOR;
						tcl_cmt_store(yytext); }
<CMTHEAD>^#Arguments{WHITE}*:.+\n	{ ctyp = ARGS; tcl_cmt_store(yytext); }
<CMTHEAD>^#Abstract{WHITE}*:.+\n	{ ctyp = BRIEF;
						tcl_cmt_store(yytext); }
<CMTHEAD>^#Results{WHITE}*:.+\n	{ ctyp = RETURN;
						tcl_cmt_store(yytext); }
<CMTHEAD>^#{WHITE}*:.+\n		tcl_cmt_store(yytext);

	/* Start new Tcl Block */
\{		tcl_block_start(yylineno);

\}		{ tcl_block_end(tcl.stack.pop(), yylineno); }

class.*\n	tcl_class_init(yytext, yylineno);

	/* TODO method has to be processed seperate */
^{WHITE}*(public|private|protected){0,1}{WHITE}*(body|proc|method){WHITE}+{NONWHITE}+{WHITE}+	{ tcl_func_name(yytext);
						yy_push_state(FUNCARGS); }

<FUNCARGS>.*\n		{ tcl_func_args(yytext, yylineno); }

<CMTRANGE>.		/* store */
<CMTRANGE>#%		{ yy_pop_state(); yyless(0); }

<CMTARGS>.		/* store */
<CMTARGS>#%		{ yy_pop_state(); yyless(0); }

<FUNCBODY>#.*\n		{ tcl_func_body(yytext); }
<FUNCBODY>\{		{ tcl_func_body(yytext); }
<FUNCBODY>\}		{ tcl_func_body(yytext); }
<FUNCBODY>\"		{ tcl_func_body(yytext); }
<FUNCBODY>\n		{ tcl_func_body(yytext); }
<FUNCBODY>{WHITE}	{ tcl_func_body(yytext); }
<FUNCBODY>[^ \t\{\}\"\n]*	{ tcl_func_body(yytext); }


<*>.|\n			/* discard */;

%%
//------------------------------------------------------------
// Functions
void tcl_error(QCString func, int line, QCString msg)
{	//todo implement for error handling
	printf("ERROR in %s at line %d: %s\n",(const char*)func,
	       line,(const char*)msg);
	exit(EXIT_FAILURE);
}

//! creates new Entry object without any data
Entry* tcl_entry_new()
{
	Entry *newEntry = new Entry;
	newEntry->section = Entry::EMPTY_SEC;
	newEntry->name = "";
	newEntry->fileName = tcl.file_name;
	newEntry->protection = Public;
	initGroupInfo(newEntry);
	tcl.entry.insert(0, newEntry);

	return newEntry;
}

//! merges two entries together
void tcl_merge_entry(Entry* e1, Entry* e2)
{
	// TODO
	(void)e1;
	(void)e2;
}

//! stores the header to the current Entry Object
void tcl_cmt_store(QCString txt)
{
//	QCString txt = str;
//	Entry e_tmp = tcl_entry_new();
	txt.remove(0,txt.find(':'));	//remove type qualifier
	txt = txt.stripWhiteSpace();	//remove whitepsaces at begin + end

	switch(ctyp) {	//Todo: Implement storing of comment
	default: printf("Ctyp: %d Text: %s\n",ctyp,(const char *)txt); break;
	}
}

//! opens a new block, stores context onto the stack
void tcl_block_start(int line)
{
	if(tcl.t_current != NULL) {
		tcl.stack.push(tcl.t_current);
		tcl.t_current = NULL;
	} else {
		tcl_context* c = new tcl_context();
		c->e_current = NULL;
		c->e_inside = tcl.e_inside;
		tcl.stack.push(c);
	}
}

//! finishes an entry after the end of the block
void tcl_block_end(tcl_context* context, int line)
{
	if(context->e_current != NULL) {
		context->e_current->bodyLine = context->line0;
		context->e_current->endBodyLine = line;
	}

	tcl.e_inside = context->e_inside;

	//	tcl.e_namespace = context->e_namespace;
	//	tcl.e_class = context->e_class;
	//	tcl.e_function = context->e_function;

}

//! inits new class entry
void tcl_class_init(QCString txt, int line)
{
	QCString name;
	QRegExp white("[ \\t]");
	QRegExp nonwhite("[^ \\t\{]");
	int index;

	index = txt.find('{');
	if(index == -1)
		tcl_error(__FUNCTION__,__LINE__,
			  "couldn't find an opening brace!");

	yyless(index);	//put everything excluding opening brace back to scanner

	index = txt.find(white);	//find end of "class"
	if(index == -1)		//error
		tcl_error(__FUNCTION__,__LINE__,"couldn't find whitespace");
	txt.remove(0,index);

	index = txt.find(nonwhite);
	if(index == -1)
		tcl_error(__FUNCTION__,__LINE__,"couldn't find a class name");
	txt.remove(0,index);

	index = txt.find(white);
	if(index == -1) {
		index = txt.find('{');
		if(index == -1)
			tcl_error(__FUNCTION__,__LINE__,
				  "should not be reached, { was already found");
	}

	name = txt.left(index);

	//create new context
	tcl.t_current = new tcl_context();
	tcl.t_current->e_inside = tcl.e_inside;

	//check if some data were already collected
	if(tcl.e_current != NULL) {	//todo nochmal nachdenken ob notwendig
		tcl.e_current->name = name;
		tcl.e_current->section = Entry::CLASS_SEC;

		Entry* e_lookup = tcl.cl.find(name);
		if(e_lookup != NULL) {
			tcl_merge_entry(e_lookup, tcl.e_current);
		} else {
			tcl.cl.insert((const char*)name, tcl.e_current);
			tcl.entry.insert(0, tcl.e_current);
		}
	} else {
		tcl.e_current = tcl_entry_new();
		tcl.e_current->name = name;
		tcl.e_current->section = Entry::CLASS_SEC;

		tcl.cl.insert(name, tcl.e_current);
		tcl.entry.insert(0, tcl.e_current);
	}

	tcl.e_inside->addSubEntry(tcl.e_current);
	tcl.t_current->e_current = tcl.e_current;
	tcl.e_inside = tcl.e_current;

	tcl.e_current = NULL;
	tcl.protection = Public;

	printf("Klasse: |%s|\n",(const char*)name);
}

//! handles function analysing
void tcl_func_name(QCString txt)
{
	QCString prot, typ, name;
	QRegExp white("[ \\t]");
	QRegExp letter("[^ \\t]");
	int index;

	txt = txt.simplifyWhiteSpace(); //remove spaces at begin + end
	                                //+ replace multiple spaces by 1 space
	index = txt.find(white);	//find first part of command
	if(index == -1)		//error
		tcl_error(__FUNCTION__,__LINE__,"couldn't find whitespace");
	prot = txt.left(index);
	if(prot == "public") {
		tcl.protection = Public;
	} else if(prot == "private") {
		tcl.protection = Private;
	} else if(prot == "protected") {
		tcl.protection = Protected;
	} else { //no protection found
		typ = prot;
	}
	txt.remove(0,index+1); //remove copied string + whitespace

	if(typ.isEmpty()) { //protection was included?
		index = txt.find(white);
		if(index == -1)
			tcl_error(__FUNCTION__,__LINE__,
				  "couldn't find space after protection");
		typ = txt.left(index);
		txt.remove(0,index+1); //remove string + whitespace
	}

	//	index = txt.find(white);	//find end of name
	//	if(index == -1)
	//	tcl_error(__FUNCTION__,__LINE__,"couldn't find end of name");
	name = txt;

	printf("Funktion: |%s|\n",(const char*)name);

	//processing of name
	if(typ == "body") {
		//TODO
	} else if(typ == "method" || typ == "proc") {
		//check if some data were already collected
		if(tcl.e_current != NULL) {
			tcl.e_current->name = name;
			tcl.e_current->type = typ;
			tcl.e_current->protection = tcl.protection;
			tcl.protection = Public;
			tcl.e_current->section = Entry::FUNCTION_SEC;
		} else {
			tcl.e_current = tcl_entry_new();
			tcl.e_current->name = name;
			tcl.e_current->type = typ;
			tcl.e_current->protection = tcl.protection;
			tcl.protection = Public;
			tcl.e_current->section = Entry::FUNCTION_SEC;
		}
	} else {
		tcl_error(__FUNCTION__,__LINE__,"unrecongnised function typ");
	}
}

//! stores Argument string, if end is false, arg string has more lines
void tcl_func_args(QCString txt, int line)
{
	QRegExp cbrace("\\}"), obrace("\\{");
	QRegExp brace("[\\}\\{]");
	QRegExp alnum("[A-Za-z0-9_]"), nalnum("[^A-Za-z0-9_]");
	QRegExp white("[ \\t]"), nonwhite("[^ \\t\\n]");
	int index, len;
	int obcnt = 0;
	int cbcnt = 0;

	len = txt.length();

	if(tcl.func_args_bcnt == 0) {
		index = txt.find(obrace);
		if(index == -1) { //proc a args command
			index = txt.find(white);
			if(index == -1)
				tcl_error(__FUNCTION__,__LINE__,
					  "should contain whitespace");
			tcl.e_current->args = txt.left(index-1);
		} else if(index > txt.find(alnum)) {
			//proc a args { commands }
			//Arguments is only 1 word
			tcl.e_current->args =
				txt.left(index-1).simplifyWhiteSpace();

			//TODO Arglist!
		} else {
			++tcl.func_args_bcnt;
			tcl.func_args_temp += "{";
			txt.remove(0,index+1);
		}
	}
	printf("init: bcnt: %d\n",tcl.func_args_bcnt);

	while(tcl.func_args_bcnt != 0) {
		index = txt.find(nonwhite);
		printf("while: txt: |%s|\n",(const char*)tcl.func_args_temp);
		if(index == -1) {
			printf("break\n");
			break; //newline appeard, without beeing done
		}
		printf("while: bcnt: %d, %d, |%c|\n",tcl.func_args_bcnt,index,txt[index]);

		switch(txt[index]) {
		case '{':
			++tcl.func_args_bcnt;
			tcl.func_args_temp += " {";
			txt.remove(0,index+1);
			break;
		case '}':
			--tcl.func_args_bcnt;
			tcl.func_args_temp += "} ";
			txt.remove(0,index+1);
			break;
		default: //any letter
			txt.remove(0,index); //remove leading whitespaces
			index = txt.find(nalnum);
			assert(index != -1);
			if(tcl.func_args_bcnt < 3) {
				if(tcl.a_current == NULL) {
					//new Argument
					tcl.a_current = new Argument();
					tcl.e_current->argList->
						append(tcl.a_current);
					tcl.a_current->name = txt.left(index);
					tcl.func_args_temp += txt.left(index);
					txt.remove(0,index);
				}

				if(tcl.func_args_bcnt == 2) {
					//lookup for defval
					index = txt.find(nonwhite);
					if(index != -1 &&
					   txt.mid(index,1).find(alnum) != -1) {
						//txt[index] is alnum->defval
						txt.remove(0,index);
						index = txt.find(nalnum);

						tcl.a_current->defval =
							txt.left(index);

						tcl.func_args_temp += " " +
							txt.left(index);

						txt.remove(0,index);

						tcl.a_current = NULL;
					}
				} else {
					tcl.a_current = NULL;
				}
			} else {
				index = txt.find(QRegExp("[A-Za-z0-9_ \\t]+"));
				assert(index != -1);

				tcl.a_current->defval += txt.left(index);
				tcl.a_current = NULL;
				tcl.func_args_temp += " " + txt.left(index);
				txt.remove(0,index);
			}
		}
	}

	if(tcl.func_args_bcnt == 0) {
		tcl.a_current = NULL;
		tcl.e_current->args = tcl.func_args_temp.simplifyWhiteSpace();

		index = txt.find(obrace);
		assert(tcl.e_current != NULL);
		if(index == -1) {
			//no new block -> function is over after the line
			tcl.e_inside->addSubEntry(tcl.e_current);
			tcl.e_current = NULL;
		} else {
			yyless(index); //push everything else back for reading
			tcl.t_current = new tcl_context();
			tcl.t_current->e_current = tcl.e_current;
			tcl.t_current->e_inside = tcl.e_inside;
			tcl.e_inside->addSubEntry(tcl.e_current);

			tcl.e_inside = tcl.e_current;

			tcl.e_current = NULL;
			tcl.stack.push(tcl.t_current);
		}

		tcl.func_args_temp = "";  //clear storage string
		yyless(len - txt.length());
		yy_pop_state();

	}
}

//! handles the function body, including Procedure Range and Procedure Args
void tcl_func_body(QCString txt)
{
	(void)txt;
}



//! inits for tcl scanner
void tcl_init(void)
{
	tcl.config_autobrief = Config_getBool("JAVADOC_AUTOBRIEF");
	tcl.input_string = NULL;
	tcl.input_position = 0;
	tcl.file_name = "";
	tcl.this_parser = NULL;

	tcl.func_args_temp = "";
	tcl.func_body_temp = "";
	tcl.func_args_bcnt = 0;
	tcl.e_main = NULL;
	tcl.e_current = NULL;
	tcl.e_inside = NULL;

	tcl.stack.clear();
	tcl.ns.clear();
	tcl.cl.clear();
	tcl.fn.clear();

	tcl.protection = Public;

	yylineno = 1;
	tclscanYYrestart(tclscanYYin);
}

static void tcl_parse()
{
	tcl.e_inside = tcl.e_main;

	Entry* e = tcl_entry_new();
	e->name = "ns1";
	e->section = Entry::NAMESPACE_SEC;
	tcl.e_inside->addSubEntry(e);

	yyrestart(yyin);
	yylineno = 1;
	yylex();

	//TODO!!
	/*	if(!tcl.stack.isEmpty()) //check if all braces were closed
		tcl_error(__FUNCTION__,__LINE__,
		"Stack is not empty! File: " + tcl.file_name); */
}

//! Parse text file and build up entry tree.
void TclLanguageScanner::parseInput(const char *fileName,
				    const char *input,
				    Entry *root)
{
	QFile myFile;

	myFile.setName(fileName);
	if (!myFile.open(IO_ReadOnly)) return;

	printf("Parsing '%s'...\n",fileName);

	//printf("Debug: %s\n", input);

	groupEnterFile(fileName,yylineno);

	tcl_init();
	tcl.file_name = fileName;
	tcl.input_string = input;
	tcl.this_parser = this;
	tcl.e_main = root; // toplevel entry
	tcl_parse();


	/*	Entry *e1 = new Entry;
	e1->section = Entry::FUNCTION_SEC;
	e1->startLine = 1;
	e1->type = "int";
	e1->name = "k1";
	e1->args = "(int a, int b)";
	e1->lang = SrcLangExt_Tcl;
	e1->brief = "Kurze Doku Nr.1";
	e1->fileName = fileName;

	Entry *e2 = new Entry;
	e2->section = Entry::GROUPDOC_SEC;
	e2->groupDocType = Entry::GROUPDOC_ADD;
	e2->name = "mem1";
	e2->fileName = fileName;

	Entry *ef = new Entry;
	ef->name = fileName;
	ef->section = Entry::SOURCE_SEC;

	root->addSubEntry(ef);

	if(strcmp(fileName,"/home/ben/Projects/doctool/tcl_examples/component.tcl") == 0) {
	    ef->addSubEntry(e1);
	} else {
	    ef->addSubEntry(e2);
	}
	//	initGroupInfo(e1);*/
	/*if(strcmp(fileName,"/home/ben/Projects/doctool/tcl_examples/component.tcl") == 0) {
		Entry* ec = tcl_entry_new();
		ec->name = "Testklasse";
		ec->section = Entry::CLASS_SEC;
		}*/

	groupLeaveFile(tcl.file_name,yylineno);
	root->program.resize(0);
	myFile.close();

	/*QList<Entry> *chil = new QList<Entry>(*(root->children()));
	Entry* en = chil->first();
	printf("%s\n",(const char*)en->name);*/



}

//! Parse file and codify.
void TclLanguageScanner::parseCode(CodeOutputInterface & codeOutIntf,
				   const char * scopeName,
				   const QCString & input,
				   bool isExampleBlock,
				   const char * exampleName,
				   FileDef * fileDef,
				   int startLine,
				   int endLine,
				   bool inlineFragment,
				   MemberDef *memberDef,
				   bool showLineNumbers
				   ) {
	return;
}

bool TclLanguageScanner::needsPreprocessing(const QCString &extension) {
  (void)extension;
  return FALSE;
}

void TclLanguageScanner::resetCodeParserState() {
}

void TclLanguageScanner::parsePrototype(const char *text) {
  (void)text;
}

static int yyread(char *buf,int max_size)
{
  int c=0;

  *buf = '\0';
  while ( c < max_size && tcl.input_string[tcl.input_position] )
  {
    *buf = tcl.input_string[tcl.input_position++] ;
    c++; buf++;
  }
  //printf("Read from=%d size=%d max=%d c=%d\n",tcl.input_position,strlen(&tcl.input_string[tcl.input_position]),max_size,c);
  return c;
}

//----------------------------------------------------------------------------

#if !defined(YY_FLEX_SUBMINOR_VERSION)
//----------------------------------------------------------------------------
extern "C" { // some bogus code to keep the compiler happy
  void fscannerYYdummy() { yy_flex_realloc(0,0); }
}
#endif

