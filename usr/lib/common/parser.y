/*
 * COPYRIGHT (c) International Business Machines Corp. 2013-2017
 *
 * This program is provided under the terms of the Common Public License,
 * version 1.0 (CPL-1.0). Any use, reproduction or distribution for this
 * software constitutes recipient's acceptance of CPL-1.0 terms which can be
 * found in the file LICENSE file or at
 * https://opensource.org/licenses/cpl1.0.php
 */

%{
/*
 * Parse openCryptoki's config file.
 */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>

#include "slotmgr.h"
#include "configparser.h"

struct parsefuncs *parsefuncs;
void *parsedata;

extern FILE *yyin;
extern int yyparse();
extern void yyerror(const char *s);
extern int line_num;
extern int yylex();

struct ock_key {
	char *name;
	keyword_token token;
};

static const struct ock_key ock_keywords[] = {
	{"stdll",       	KW_STDLL},
	{"description", 	KW_SLOTDESC},
	{"manufacturer",	KW_MANUFID},
	{"hwversion",		KW_HWVERSION},
	{"firmwareversion",	KW_FWVERSION},
	{"confname",		KW_CONFNAME},
	{"tokname",		KW_TOKNAME},
	{"tokversion",		KW_TOKVERSION}
};

int lookup_keyword(const char *key);

%}

%union {
	char *str;
	unsigned int num;
    int err;
}

%token EQUAL DOT SLOT EOL OCKVERSION BEGIN_DEF END_DEF
%token <str> STRING
%token <str> KEYWORD
%token <num> INTEGER
%token <num> TOKVERSION
%token <str> COMMENT

%%

config_file:
	config_file sections
	|
	;

sections:
	version_def eolcomments
	| SLOT INTEGER BEGIN_DEF
	{
        if (parsefuncs->begin_slot)
            parsefuncs->begin_slot(parsedata, $2, 0);
	} eolcomments keyword_defs END_DEF
	{
        if (parsefuncs->end_slot)
            parsefuncs->end_slot(parsedata);
	}
	| SLOT INTEGER EOL BEGIN_DEF
	{
        if (parsefuncs->begin_slot)
            parsefuncs->begin_slot(parsedata, $2, 1);
    } eolcomments keyword_defs END_DEF
	{
        if (parsefuncs->end_slot)
            parsefuncs->end_slot(parsedata);
	}
	| eolcomments
	;

version_def:
    OCKVERSION STRING
    {
        if (parsefuncs->version)
            parsefuncs->version(parsedata, $2);
        free($2);
    }

line_def:
    STRING EQUAL TOKVERSION
    {
        int kw;

        if (parsefuncs->key_vers) {
            kw = lookup_keyword($1);
            if (kw != -1)
                parsefuncs->key_vers(parsedata, kw, $3);
            else if (parsefuncs->parseerror)
                parsefuncs->parseerror(parsedata);
        }
        free($1);
    }
    |
    STRING EQUAL STRING
    {
        int kw;

        if (parsefuncs->key_str) {
            kw = lookup_keyword($1);
            if (kw != -1)
                parsefuncs->key_str(parsedata, kw, $3);
            else if (parsefuncs->parseerror)
                parsefuncs->parseerror(parsedata);
        }
        free($1);
        free($3);
    }

keyword_defs:
    line_def eolcomments keyword_defs
    |
    eolcomments keyword_defs
    |
    /* empty */

eolcomments:
    eolcomment eolcomments
    |
    eolcomment

eolcomment:
    COMMENT EOL
    {
        if (parsefuncs->eolcomment)
            parsefuncs->eolcomment(parsedata, $1);
        if (parsefuncs->eol)
            parsefuncs->eol(parsedata);
        free($1);
    }
    |
    EOL
    {
        if (parsefuncs->eol)
            parsefuncs->eol(parsedata);
    }

%%

void
yyerror(const char *s)
{
	fprintf(stderr, "parse error on line %d: %s\n", line_num, s);
}

int
lookup_keyword(const char *key)
{
	int i;

	for (i = 0; i < KW_MAX ; i++ ) {
		if (strncmp(key, ock_keywords[i].name, strlen(key)) == 0)
			return ock_keywords[i].token;
	}
	/* if we get here that means did not find a match... */
	return -1;
}

const char *keyword_token_to_str(int tok)
{
	return tok < KW_MAX ? ock_keywords[tok].name : "<UNKNWON>";
}

int
load_and_parse(const char *configfile, struct parsefuncs *funcs, void *private)
{

	FILE *conf;

	extern FILE *yyin;

	conf = fopen(configfile, "r");

	if (!conf) {
		fprintf(stderr, "Failed to open %s: %s\n", configfile, strerror(errno));
		return -1;
	}

	yyin = conf;
	parsefuncs = funcs;
	parsedata = private;
    
	do {
		yyparse();

	} while (!feof(yyin));

	fclose(conf);
	parsefuncs = NULL;
	parsedata = NULL;

	return 0;
}