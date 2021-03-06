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
        QCString cmt_store_temp;
        QCString cmt_proc_temp;
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
// Prototypes
static int yyread(char *buf, int max_size);
void tcl_var_name(QCString txt, int line);
void tcl_func_name(QCString txt);
void tcl_func_args(QCString txt, int line);
void tcl_entry_merge(Entry *res, Entry *e);
void tcl_cmt_proc(bool args, int line);

void cmt_briefdesc(QCString txt);
void cmt_finish(int line);
void cmt_class(QCString txt, int line);
void cmt_inherit(QCString txt, int line);
void cmt_namespace(QCString txt, int line);

void tcl_block_start(int line);
void tcl_block_end(tcl_context* context, int line);

const char* lstripchar(QCString txt, char c);
const char* rstripchar(QCString txt, char c);

//-----------------------------------------------------------------------
#undef YY_INPUT
#define YY_INPUT(buf,result,max_size) result=yyread(buf,max_size);
//-----------------------------------------------------------------------
%}

WHITE [ \t]
NONWHITE [^ \t\n]
KEYWORD [a-zA-Z0-9:_+.-]
KEYWORDS [ a-zA-Z0-9:_+.-]

%option yylineno
%option noyywrap
%option stack

/* Start Conditions */
%x QUOTE
%x QUOTEESC
%x ESC
%x FUNCARGS
%x CMTARGS
%x CMTRANGE

%x FUNCBODY

%%
"\\"                    yy_push_state(ESC);
<ESC>.|\n               yy_pop_state();
"\""                    yy_push_state(QUOTE);
<QUOTE>"\\"             yy_push_state(QUOTEESC);
<QUOTEESC>.|\n          yy_pop_state();
<QUOTE>"\""             yy_pop_state(); 

^{WHITE}*#[^%].*                                       /* discard */
^{WHITE}*#%{WHITE}*@history.*                          /* discard */
^{WHITE}*#%{WHITE}*@hide.*                             /* discard */

^{WHITE}*#%ProcedureRange{WHITE}*                      yy_push_state(CMTRANGE);
^{WHITE}*#%ProcedureArgs{WHITE}*                       yy_push_state(CMTARGS);

^{WHITE}*#%.*                                          cmt_briefdesc(yytext);

info{WHITE}+[^\"\{\}\n]*\n      /* exclude info command */

"{"               tcl_block_start(yylineno);
"}"             { tcl_block_end(tcl.stack.pop(), yylineno); }

namespace{WHITE}+eval{WHITE}+{KEYWORD}+{WHITE}*/\{    { cmt_finish(yylineno); cmt_namespace(yytext,yylineno); }
class{WHITE}+{KEYWORD}+{WHITE}*/\{                    { cmt_finish(yylineno); cmt_class(yytext, yylineno); }
inherit{WHITE}+{KEYWORDS}*                              cmt_inherit(yytext, yylineno);

{WHITE}*(constructor|destructor){WHITE}*/\{                                                        { yy_push_state(FUNCARGS); tcl_func_name(yytext); yyless(strlen(yytext)-1); }
{WHITE}*(public|private|protected){0,1}{WHITE}*(body|proc|method){WHITE}+[^ \t\n\{\}]+{WHITE}+/\{  { cmt_finish(yylineno); yy_push_state(FUNCARGS); tcl_func_name(yytext); }

{WHITE}*(public|private|protected){0,1}{WHITE}*variable{WHITE}+{KEYWORD}+[ \t\n]              { tcl_var_name(yytext, yylineno); }

<FUNCARGS>.*\n              { tcl_func_args(yytext, yylineno); }

<CMTRANGE>\n                  tcl.cmt_proc_temp += "<br />\n";
<CMTRANGE>.                   tcl.cmt_proc_temp += yytext;
<CMTRANGE>#%End.*\n         { tcl_cmt_proc(false, yylineno); yy_pop_state(); }
<CMTRANGE>#%ProcedureArgs{WHITE}*\n   { tcl_cmt_proc(false, yylineno); yy_pop_state(); yyless(0); }

<CMTARGS>\n                   tcl.cmt_proc_temp += "<br />\n";
<CMTARGS>.                    tcl.cmt_proc_temp += yytext;
<CMTARGS>#%End.*\n          { tcl_cmt_proc(true, yylineno); yy_pop_state(); }
<CMTARGS>#%ProcedureRange{WHITE}*\n   { tcl_cmt_proc(true, yylineno); yy_pop_state(); yyless(0); }

<*>.|\n                 /* discard */;

%%
//------------------------------------------------------------
// Functions
void tcl_error(QCString func, int line, QCString msg)
{       //todo implement for error handling
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
        newEntry->lang = SrcLangExt_Tcl;
        initGroupInfo(newEntry);
        tcl.entry.insert(0, newEntry);

        //fprintf(stderr,"New Entry, |%s|\n",(const char*)tcl.e_inside->name);

        return newEntry;
}

//! merges two entries together
void tcl_merge_entry(Entry* e1, Entry* e2)
{
        // TODO
        (void)e1;
        (void)e2;
}

void cmt_briefdesc(QCString txt)
{
//fprintf(stdout,"cmt_briefdesc: txt: '%s'\n", (const char*)txt);
        txt = txt.simplifyWhiteSpace();                 // remove white spaces inside and outside
        txt.remove(0,2);                                // remove #%
        txt = txt.stripWhiteSpace();                    // remove whitespaces
	if (txt.isEmpty()) return;                      // !txt.remove crashes on null string!
	if (tcl.cmt_store_temp.isEmpty()) {tcl.cmt_store_temp += "@brief";}   // per default it's a brief description
        tcl.cmt_store_temp += "\n" + txt;
}

//! stores comment to an entry
void cmt_finish(int line)
{
//fprintf(stdout,"proc cmt_finish: cmt_store_temp: '%s'\n", (const char*)tcl.cmt_store_temp);
        int pos = 0;
        bool newentry=0;

        //      printf("cmt_store: |%s|\n", (const char*)tcl.cmt_store_temp);
        if(tcl.cmt_store_temp.isEmpty()) return;

        if(tcl.e_current == NULL) tcl.e_current = tcl_entry_new();

        while(parseCommentBlock(tcl.this_parser, tcl.e_current, tcl.cmt_store_temp, tcl.file_name,
                                          line, FALSE, tcl.config_autobrief,
                                FALSE, tcl.protection, pos, newentry)) {

             if(newentry) {
                    fprintf(stdout,"New Entry! |%d|\n",line);
                    newentry = false;
                    tcl.e_inside->addSubEntry(tcl.e_current);
                    tcl.e_current = tcl_entry_new();
             }
        }

        if(newentry) {
                fprintf(stdout,"New Entry! |%d|\n",line);
                tcl.e_inside->addSubEntry(tcl.e_current);
                tcl.e_current = tcl_entry_new();
        }
}

//! handles procedure range and args
void tcl_cmt_proc(bool args, int line)
{
        BufStr in(16), out(16);
        Entry *e;
        int pos=0;
        bool newentry=0;
        tcl_context *t = tcl.stack.top();

        if(tcl.cmt_proc_temp.isEmpty()) return;
        if(t == NULL) return;

        e = t->e_current;

        if(e == NULL) return;

        if(args)
                tcl.cmt_proc_temp = "\\par ProcedureArgs:\n" + tcl.cmt_proc_temp;
        else
                tcl.cmt_proc_temp = "\\par ProcedureRange:\n" + tcl.cmt_proc_temp;

        parseCommentBlock(tcl.this_parser, e, tcl.cmt_proc_temp, tcl.file_name,
                                          line, FALSE, tcl.config_autobrief,
                                          FALSE, tcl.protection, pos,newentry);

        tcl.cmt_proc_temp = "";
}

//! opens a new block, stores context onto the stack
void tcl_block_start(int line)
{
//fprintf(stdout,"tcl_block_start: line: %i\n", line);
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
//fprintf(stdout,"tcl_block_end: line: %i\n", line);
        if(context == NULL) {
                fprintf(stderr,"%s: Warning, brace that was never opened found at line %d.\n",(const char*)tcl.file_name,line);
                return;
                //tcl_error(__FUNCTION__,line,"Syntax error. A closing Brace too much!");
        }
        if(context->e_current != NULL) {
                context->e_current->bodyLine = context->line0;
                context->e_current->endBodyLine = line;
        }

        tcl.e_inside = context->e_inside;
}

//! inits new namespace
void cmt_namespace(QCString txt, int line)
{
fprintf(stdout,"cmt_namespace: txt: '%s'\n", (const char*)txt);
        QCString parent;
        int index;
        Entry* e;
        Entry* inside = tcl.e_inside;

	// remove "namespace eval" so that name stands alone
	txt = txt.simplifyWhiteSpace();
	txt.remove(0,14); // namespace eval = 14 characters
	txt = txt.stripWhiteSpace();
	txt = lstripchar(txt, ':');
	if (txt.isEmpty()) {return;}

        //namespace hierarchy processing
        if(txt.contains(':')) {
                index = txt.find(':'); //first time it exists
                do {
                        parent = txt.left(index);
                        txt.remove(0,index);
			txt = lstripchar(txt, ':');
                        if(!parent.isEmpty()) {
                            //create parent entries for namespaces
                            e = tcl.ns.find(parent);
                            if(e == NULL) {
                                e = tcl_entry_new();
                                e->name = parent;
                                e->section = Entry::NAMESPACE_SEC;
                                tcl.ns.insert(txt,e);
                                tcl.entry.insert(0, e);
                                inside->addSubEntry(e);
                                inside = e;
                                e = NULL;
                            }
                        }
                        index = txt.find(':');
                } while(index != -1);
        }
        //now only name is left

        //create new context
        tcl.t_current = new tcl_context();
        tcl.t_current->e_inside = tcl.e_inside;

        //check if some data were already collected
        if(tcl.e_current == NULL)
                tcl.e_current = tcl_entry_new();

        tcl.e_current->name = txt;
        tcl.e_current->section = Entry::NAMESPACE_SEC;
        tcl.ns.insert(txt, tcl.e_current);
        tcl.entry.insert(0, tcl.e_current);

        inside->addSubEntry(tcl.e_current);
        tcl.t_current->e_current = tcl.e_current;
        tcl.e_inside = tcl.e_current;

        tcl.cmt_store_temp = "";

        tcl.e_current = NULL;
        tcl.protection = Public;
}

const char* lstripchar(QCString txt, char c) {
        if (txt.isEmpty()) {return txt;}
        while (txt.at(0) == c) {
	     txt.remove(0,1);
	     if (txt.isEmpty()) {return txt;}
        }
	return txt;
}

const char* rstripchar(QCString txt, char c) {
        if (txt.isEmpty()) {return txt;}
        while (txt.at(txt.length()-1) == c) {
	     txt.remove(txt.length()-1,1);
	     if (txt.isEmpty()) {return txt;}
        }
	return txt;
}

//! inits new class entry
void cmt_class(QCString txt, int line)
{
fprintf(stderr,"cmt_class: '%s'\n",(const char*)txt);
	// remove "class" so that name stands alone
	txt = txt.stripWhiteSpace();
	txt.remove(0,5); // class = 5 characters
	txt = txt.stripWhiteSpace();

        //create new context
        tcl.t_current = new tcl_context();
        tcl.t_current->e_inside = tcl.e_inside;

        //check if some data were already collected
        if(tcl.e_current != NULL) {
                tcl.e_current->name = txt;
                tcl.e_current->section = Entry::CLASS_SEC;
                tcl.cl.insert(txt, tcl.e_current);

                tcl.entry.insert(0, tcl.e_current);
                tcl.cmt_store_temp = "";
        } else {
                tcl.e_current = tcl_entry_new();
                tcl.e_current->name = txt;
                tcl.e_current->section = Entry::CLASS_SEC;

                tcl.cl.insert(txt, tcl.e_current);
                tcl.entry.insert(0, tcl.e_current);
        }

        tcl.e_inside->addSubEntry(tcl.e_current);
        tcl.t_current->e_current = tcl.e_current;
        tcl.e_inside = tcl.e_current;

        tcl.e_current = NULL;
        tcl.protection = Public;
}

//! handles inheritance relation between classes
void cmt_inherit(QCString txt, int line)
{
fprintf(stderr,"cmt_inherit: '%s'\n",(const char*)txt);
        QRegExp white("[ \\t]");
        BaseInfo *inf;
        Entry *e = tcl.stack.top()->e_current;
        int index;

        if(e == NULL)
                tcl_error(__FUNCTION__,line,"Inherit not in an Entity");
        if(e->section != Entry::CLASS_SEC)
                tcl_error(__FUNCTION__,line,"Inherit not in a Class");

	// remove "inherit" so that name stands alone
	txt = txt.simplifyWhiteSpace();
	txt.remove(0,7); // inherit = 7 characters
	txt = txt.stripWhiteSpace();
	if (txt.isEmpty()) {return;}
	
        do {
                index = txt.find(white);
                inf = new BaseInfo(txt.left(index), Public, Normal);
                //              printf("|%s|\n",(const char*)txt.left(index));
                txt.remove(0,index+1);
                e->extends->append(inf);
        } while(index != -1);
}


//! handles function analysing
void tcl_var_name(QCString txt, int line)
{
        QCString prot, typ, name, parent;
        QRegExp white("[ \\t\\n]");
        QRegExp letter("[^ \\t\\n]");
        int index, length;

        length = txt.length();

        index = txt.find(letter);
        if(index == -1)
                tcl_error(__FUNCTION__,line, "couldn't find a letter");
        txt.remove(0,index); //remove heading spaces

        index = txt.find(white);        //find first part of command
        if(index == -1)         //error
                tcl_error(__FUNCTION__,line, "couldn't find whitespace");
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
        txt.remove(0,index); //remove copied string

        index = txt.find(letter);
        if(index == -1)
                tcl_error(__FUNCTION__,line, "couldn't find varname");
        txt.remove(0,index); //remove heading spaces

        if(typ.isEmpty()) { //protection was included?
                index = txt.find(white);
                if(index == -1)
                        tcl_error(__FUNCTION__,line,
                                          "couldn't find space after variable");
                typ = txt.left(index);
                txt.remove(0,index); //remove string

                index = txt.find(letter);
                if(index == -1)
                        tcl_error(__FUNCTION__,line, "couldn't find a letter");
                txt.remove(0,index); //remove heading spaces
        }

        index = txt.find(white);
        if(index == -1)
                tcl_error(__FUNCTION__,line,
                                  "couldn't find whitespace after name");
        name = txt.left(index);
        txt.remove(0,index);

        //fprintf(stderr,"var: |%s| |%d| |%d|\n",(const char*)name,length,txt.length());

        yyless(length-txt.length());

        if(tcl.stack.isEmpty())
                return;

        if(tcl.stack.top()->e_current == NULL)
                return;

        if(tcl.stack.top()->e_current->section != Entry::CLASS_SEC &&
           tcl.stack.top()->e_current->section != Entry::NAMESPACE_SEC)
                return;

        if(tcl.e_current == NULL) //no information at the moment
                tcl.e_current = tcl_entry_new();
        tcl.e_current->section = Entry::VARIABLE_SEC;
        tcl.e_current->type = typ;
        tcl.e_current->name = name;
        tcl.e_current->protection = tcl.protection;
        tcl.protection = Public;
        tcl.cmt_store_temp = "";

        //      printf("Var: |%s|, |%s|\n",(const char*)name, (const char*)tcl.e_inside->name);

        //      if(txt.contains("##")) {
        //      index = txt.find("##");
        //      assert(index != -1); //should not happen, was just found
        //      txt.remove(0,index+2);
        //      tcl.e_current->brief = txt;
        //      }

        tcl.e_inside->addSubEntry(tcl.e_current);
        tcl.e_current = NULL;
}

//! handles function analysing
void tcl_func_name(QCString txt)
{
fprintf(stderr,"tcl_func_name: txt: '%s'\n",(const char*)txt);
        QCString prot, typ, name, parent;
        QRegExp white("[ \\t]");
        QRegExp letter("[^ \\t]");
        int index;
        Entry* e;
        Entry* inside = tcl.e_inside;

        txt = txt.simplifyWhiteSpace(); //remove spaces at begin + end
                                        //+ replace multiple spaces by 1 space
        if(!(txt == "constructor" || txt == "destructor")) {
                index = txt.find(white);        //find first part of command
                if(index == -1)         //error
                        tcl_error(__FUNCTION__,__LINE__,
                                          "couldn't find whitespace");
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
        } //if txt == constructor/destructor, nothing to do
        name = txt;

        //      printf("Funktion: |%s|\n",(const char*)name);

        //namespace/class hierarchy processing
        if(name.contains(':') && typ == "proc") {
	        name = lstripchar(name, ':');
                index = name.find(':'); //first time it exists
                do {
                        parent = name.left(index);
			name.remove(0,index);
                        name = lstripchar(name, ':');
                        if(!parent.isEmpty()) {
                            //create parent entries for namespaces
                            e = tcl.ns.find(parent);
                            if(e == NULL)
                                    e = tcl.cl.find(parent);
                            if(e == NULL) {
                                    e = tcl_entry_new();
                                    e->name = parent;
                                    e->section = Entry::NAMESPACE_SEC;
                                    tcl.ns.insert(name,e);
                                    tcl.entry.insert(0, e);
                                    inside->addSubEntry(e);
                                    inside = e;
                                    e = NULL;
                            }
                            if(e != NULL) {
                                    inside = e;
                                    e = NULL;
                            }
                        }
                        index = name.find(':');
                } while(index != -1);
        }
        //now only name is left

        //processing of name
        if(typ == "body" || typ == "itcl::body") {
                e = tcl.fn.find(txt);
                if(e == NULL) {
                        tcl.cmt_store_temp = "";
                        if(tcl.e_current != NULL)
                                delete tcl.e_current;
                        tcl.e_current = NULL;
                        yy_pop_state();
                        return;
                }

                if(!(e->argList->isEmpty())) {
                        //fprintf(stderr,"Del: |%s| |%s|\n",(const char*)e->name,(const char*)e->args);
                        
                        e->args.resize(0);
                        e->argList->clear();
                        //                      delete e->argList;
                        //e->argList = new ArgumentList();
                }

                        //                      tcl_error(__FUNCTION__,__LINE__,
                //                                        "Body Function of a non-existant Function");
                if(tcl.e_current != NULL) {
                        int pos = 0;
                        bool newentry, init=true;
                        int line;

                        delete tcl.e_current;
                        tcl.e_current = e;

                        while(parseCommentBlock(tcl.this_parser, tcl.e_current, tcl.cmt_store_temp, tcl.file_name,
                                          line, FALSE, tcl.config_autobrief,
                                FALSE, tcl.protection, pos,newentry)) {

                                if(newentry) {
                                        //                                      printf("New Entry!\n");
                                        newentry = false;
                                        if(!init)
                                            tcl.e_inside->addSubEntry(tcl.e_current);
                                        tcl.e_current = tcl_entry_new();
                                } else {
                                        tcl.e_current->section = tcl.e_inside->section;
                                        tcl.e_current->name = tcl.e_inside->name;
                                }
                        }

                        if(newentry) {
                                //                              printf("New Entry!\n");
                                newentry = false;
                                tcl.e_inside->addSubEntry(tcl.e_current);
                                tcl.e_current = tcl_entry_new();
                        }

                } else {
                        tcl.e_current = e;
                }
                e = NULL;
        } else if(typ == "method" || typ == "proc" ||
                          name == "constructor" || name == "destructor") {
                //check if some data were already collected
                if(tcl.e_current == NULL) {
                        tcl.e_current = tcl_entry_new();
                }
                tcl.e_current->name = name;
                tcl.e_current->type = typ;
                tcl.e_current->protection = tcl.protection;
                tcl.protection = Public;
                tcl.e_current->section = Entry::FUNCTION_SEC;
                inside->addSubEntry(tcl.e_current);

                if(inside->section == Entry::CLASS_SEC ||
                   inside->section == Entry::NAMESPACE_SEC) {
                        name = inside->name + "::" + name;
                        while(inside->parent()->section == Entry::CLASS_SEC ||
                                  inside->parent()->section == Entry::NAMESPACE_SEC) {
                                inside = inside->parent();
                                name = inside->name + "::" + name;
                        }
                }
                //              printf("|%s|\n",(const char*)name);
                tcl.fn.insert(name, tcl.e_current);
        } else {
                tcl_error(__FUNCTION__,__LINE__,"unrecongnised function typ");
        }
        
        tcl.cmt_store_temp = "";
}

//! stores Argument string, if end is false, arg string has more lines
void tcl_func_args(QCString txt, int line)
{
        QRegExp cbrace("\\}"), obrace("\\{");
        QRegExp brace("[\\}\\{]");
        QRegExp alnum("[^\\}\\{ \\t\\n]"), nalnum("[\\}\\{ \\t\\n]");
        QRegExp white("[ \\t]"), nonwhite("[^ \\t\\n]");
        int index, len;

        len = txt.length();

        if(tcl.func_args_bcnt == 0) {
                index = txt.find(obrace);
                if(index == -1) { //proc a args command
                        index = txt.find(white);
                        if(index == -1) {
                                delete tcl.e_current;
                                return;
                                //                              tcl_error(__FUNCTION__,__LINE__,
                                //        "should contain whitespace");
                        }
                        tcl.e_current->args = txt.left(index);
                        tcl.a_current = new Argument();
                        //fprintf(stderr,"Argu: |%s| |%s|\n",(const char*)tcl.e_current->name,(const char*)tcl.e_current->args);
                        tcl.a_current->name = tcl.e_current->args;
                        tcl.e_current->argList->append(tcl.a_current);
                        tcl.a_current = NULL;

                        tcl.e_current = NULL;
                        tcl.func_args_temp = "";  //clear storage string
                        yy_pop_state();
                        return;

                } else if(index > txt.find(alnum) && txt.find(alnum) != -1) {
                        //proc a args { commands }
                        //Arguments is only 1 word
                        tcl.e_current->args =
                                txt.left(index).simplifyWhiteSpace();

                        tcl.a_current = new Argument();
                        //fprintf(stderr,"Argu: |%s| |%s|\n",(const char*)tcl.e_current->name,(const char*)tcl.e_current->args);
                        tcl.a_current->name = tcl.e_current->args;
                        tcl.e_current->argList->append(tcl.a_current);
                        tcl.a_current = NULL;

                        tcl.e_current = NULL;
                        tcl.func_args_temp = "";  //clear storage string
                        yy_pop_state();
                        return;
                } else {
                        ++tcl.func_args_bcnt;
                        tcl.func_args_temp += " { ";
                        txt.remove(0,index+1);
                }
        }

        while(tcl.func_args_bcnt != 0) {
                index = txt.find(nonwhite);

                if(index == -1) {
                        break; //newline appeard, without beeing done
                }

                switch(txt[index]) {
                case '{':
                        ++tcl.func_args_bcnt;
                        tcl.func_args_temp += " { ";
                        if(tcl.a_current != NULL && tcl.func_args_bcnt > 2)
                                tcl.a_current->defval += " { ";
                        txt.remove(0,index+1);
                        break;
                case '}':
                        --tcl.func_args_bcnt;
                        tcl.func_args_temp += " } ";
                        if(tcl.a_current != NULL && tcl.func_args_bcnt > 1)
                                tcl.a_current->defval += " } ";
                        if(tcl.a_current != NULL && tcl.func_args_bcnt == 1)
                                tcl.a_current = NULL;
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
                                        //fprintf(stderr,"Argu: |%s| |%s|\n",(const char*)tcl.e_current->name,(const char*)tcl.a_current->name);
                                        tcl.func_args_temp += " " +
                                                txt.left(index);
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
                                index = txt.find(QRegExp("[\\{\\}\\n]"));
                                assert(index != -1);

                                tcl.a_current->defval += txt.left(index);
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
                } else {
                        //fprintf(stderr,"ERR: %d\n",len-txt.length()+index);
                        yyless(len - txt.length() + index + 1);

                        tcl.t_current = new tcl_context();
                        tcl.t_current->e_current = tcl.e_current;
                        tcl.t_current->e_inside = tcl.e_inside;

                        tcl.e_inside = tcl.e_current;
                        tcl.stack.push(tcl.t_current);
                        tcl.t_current = NULL;
                }

                //              if(txt.contains("##")) { //look for brief
                //      index = txt.find("##");
                //      txt.remove(0,index+2);
                //      tcl.e_current->brief = txt.simplifyWhiteSpace();
                //              }

                tcl.e_current = NULL;
                tcl.func_args_temp = "";  //clear storage string
                yy_pop_state();
        }
}

//! merge 2 Entries
void tcl_entry_merge(Entry *res, Entry *e)
{
        (void)res;
        (void)e;
}

//! inits for tcl scanner
void tcl_init(void)
{
        tcl.config_autobrief = Config_getBool("JAVADOC_AUTOBRIEF");
        tcl.input_string = NULL;
        tcl.input_position = 0;
        tcl.file_name = "";
        tcl.this_parser = NULL;

        tcl.cmt_proc_temp = "";
        tcl.cmt_store_temp = "";
        tcl.func_args_temp = "";
        tcl.func_body_temp = "";
        tcl.func_args_bcnt = 0;
        tcl.e_main = NULL;
        tcl.e_current = NULL;
        tcl.e_inside = NULL;

        tcl.stack.clear();

        //tcl.ns.clear();
        //tcl.cl.clear();
        tcl.fn.clear();

        tcl.protection = Public;

        yylineno = 1;
        tclscanYYrestart(tclscanYYin);
        BEGIN(INITIAL);
}

static void tcl_parse()
{
        tcl.e_inside = tcl.e_main;

        //fprintf(stderr,"File: |%s|\n",(const char*)tcl.file_name);
        /*      tcl.e_current = tcl_entry_new();
        tcl.e_current->name = "var1";
        tcl.e_current->section = Entry::VARIABLE_SEC;
        tcl.e_current->type = "variable";
        tcl.e_main->addSubEntry(tcl.e_current);
        tcl.e_current = NULL;*/

        yyrestart(yyin);
        yylineno = 1;
        yylex();

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


        /*      Entry *e1 = new Entry;
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
        //      initGroupInfo(e1);*/
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


