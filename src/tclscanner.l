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
typedef struct {
    int type;
    int line0; //start of segment
    int line1; //end of segment
    Entry *e_current;
    Entry *e_class;
    Entry *e_function;
    Entry *e_namespace;
    Protection prot;
} tcl_context;

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
     int quote;
     QCString func_args_temp;
     int func_brace;
     QCString func_body_temp;

     Entry* e_main; // top level entry
     Entry* e_file; // entry of current file
     Entry* e_current; // currently used entry
     Entry* e_inside; // contain entry of current scan context

     QStack<tcl_context> stack; // stack of scan contexts
     QDict<Entry*> ns; // all read namespace entries
     QDict<Entry*> cl; // all read class entries
     QDict<Entry*> fn; // all read function entries
     QList<Entry*> entry; // list of all created entries
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
 void tcl_func_args(QCString txt, int line, bool end = TRUE);
 void tcl_func_body(QCString txt);
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
\{		{ tcl_context next; next.line0 = yylineno;
	next.e_current = tcl.e_current;
	tcl.e_current = NULL;
	tcl.stack.push(&next);
	printf("Klammer auf, %d\n",yylineno); }

\}		{ tcl_block_end(tcl.stack.pop(), yylineno); }

class.*\n	tcl_class_init(yytext, yylineno);

	/* TODO method has to be processed seperate */
(body|proc|method){WHITE}+[^\{\n]+(\{|\n)	{ tcl_func_name(yytext);
	yy_push_state(FUNCARGS); }

<FUNCARGS>[^\}]*\}.*\n		{ tcl_func_args(yytext, yylineno);
				yy_pop_state(); }
<FUNCARGS>[^\}]*\n	{ tcl_func_args(yytext, yylineno, FALSE); }

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
	return newEntry;
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

//! finishes an entry after the end of the block
void tcl_block_end(tcl_context* context, int line)
{
    printf("Klammer zu, %d\n",line);
}

//! inits new class entry
void tcl_class_init(QCString txt, int line)
{
	QCString name;
	QRegExp white("[ \\t]");
	QRegExp nonwhite("[^ \\t\{]");
	int index;

	printf("Text: |%s|\n", (const char*)txt);

	index = txt.find('{');
	if(index == -1)
		tcl_error(__FUNCTION__,__LINE__,
			  "couldn't find an opening brace!");

	yyless(index);	//put everything inluding opening brace back to scanner

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

	printf("Klasse: |%s|\n",(const char*)name);
}

//! handles function analysing
void tcl_func_name(QCString txt)
{
	QCString typ, name;
	QRegExp white("[ \\t]");
	QRegExp letter("[^ \\t]");
	int index;

	index = txt.find(white);	//find first part of command
	if(index == -1)		//error
		tcl_error(__FUNCTION__,__LINE__,"couldn't find whitespace");
	typ = txt.left(index);	//copy body/proc/method
	txt.remove(0,index);	//remove copied string
	index = txt.find(letter);
	if(index == -1)		//error no name
		tcl_error(__FUNCTION__,__LINE__,"couldn't find name");
	txt.remove(0,index);	//remove whitespaces

	index = txt.find(white);	//find end of name
	if(index == -1)
		tcl_error(__FUNCTION__,__LINE__,"couldn't find end of name");
	name = txt.left(index);

	//processing of name
	if(typ == "body") {
		printf("Body Function |%s|\n",(const char*)name);
	} else if(typ == "method") {
		//TODO
	} else if(typ == "proc") {
		//TODO
	} else {
		tcl_error(__FUNCTION__,__LINE__,"unrecongnised function typ");
	}
}

//! stores Argument string, if end is false, arg string has more lines
void tcl_func_args(QCString txt, int line, bool end)
{
	if(end) {
		QRegExp cbrace("\\}");
		QRegExp obrace("\\{");
		int index;

		index = txt.find(cbrace);
		if(index == -1)
			tcl_error(__FUNCTION__,__LINE__,
					  "should contain a brace");

		if(!tcl.func_args_temp.isEmpty())	//insert space
			tcl.func_args_temp += " ";
		tcl.func_args_temp += txt.left(index);

		// TODO Process ARGS
		printf("%s: %s | %d\n",__FUNCTION__,
		       (const char*)tcl.func_args_temp, line);

		index = txt.find(obrace);
		if(index == -1) {
			//no new block -> function is over after the line
			//-> do not insert Entry to current Entry
		} else {
			//TODO copy entry correct
			tcl_context next;
			next.line0 = yylineno;
			next.e_current = tcl.e_current;
			tcl.e_current = NULL;
			tcl.stack.push(&next);
			printf("Klammer auf, %d\n",yylineno);
		}

		tcl.func_args_temp = "";  //clear storage string

	} else {
		txt.stripWhiteSpace(); //remove whitespace at beginning and end
		if(!tcl.func_args_temp.isEmpty())
			tcl.func_args_temp += " ";
		tcl.func_args_temp += txt;
	}
}

//! handles the function body, including Procedure Range and Procedure Args
void tcl_func_body(QCString txt)
{
	if(tcl.quote) {
		if(txt == "\"")
			tcl.quote = 0;
	} else {
		if(txt == "\"") {
			tcl.quote = 1;
		} else if(txt == "{") {
			tcl.func_brace++;
		} else if(txt == "}") {
			tcl.func_brace--;
			if(tcl.func_brace == 0) { //function is over
				yy_pop_state();
				printf("Function over\n");
			}
		} else if(txt == "\"") {

		} else if(txt == "#%ProcedureRange") {
			/* TODO Processing */
		} else if(txt == "#%ProcedureArgs") {
			/* TODO Processing */
		} else if(txt == "#%EndArgs") {
			/* TODO Processing */
		}
	}
}



//! inits for tcl scanner
void tcl_init(void)
{
    tcl.quote = 0;
    tcl.func_brace = 0;
}

//! Parse text file and build up entry tree.
void TclLanguageScanner::parseInput(const char *fileName,
				    const char *input,
				    Entry *root) {
	QFile myFile;

	myFile.setName(fileName);
	if (!myFile.open(IO_ReadOnly)) return;

	printf("Parsing '%s'...\n",fileName);

	printf("Debug: %s\n", input);
	yylineno = 0;

	groupEnterFile(fileName,yylineno);

	tcl.input_string = NULL;
	tcl.input_position = 0;
	tclscanYYrestart(tclscanYYin);
/*****************************************
  tcl_init();
  tcl.code = NULL;
  tcl.input_string = input;
  tcl.file_name = fileName;
  tcl.this_parser = this;
  tcl.entry_main          = root; // toplevel entry
  tcl_parse();
*****************************************/
	tcl.input_string = input;

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

	yylineno = 1;
	tclscanYYlex();
	groupLeaveFile(tcl.file_name,yylineno);
	root->program.resize(0);
	myFile.close();



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

