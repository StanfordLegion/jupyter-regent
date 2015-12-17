# Copyright 2015 Stanford University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

from pygments.lexers import LuaLexer
from pygments.lexer import include, bygroups, default, combined
from pygments.token import Text, Comment, Operator, Keyword, Name, String, \
    Number, Punctuation

__all__ = ['RegentLexer']

class RegentLexer(LuaLexer):
    """
    For `Regent <http://regent-lang.org>`_ source code.
    """

    name = 'Regent'
    aliases = ['regent']
    filenames = ['*.rg']
    mimetypes = ['text/x-regent', 'application/x-regent']

    tokens = {
        'root': [
            # lua allows a file to start with a shebang
            (r'#!(.*?)$', Comment.Preproc),
            default('base'),
        ],
        'base': [
            (r'(?s)--\[(=*)\[.*?\]\1\]', Comment.Multiline),
            ('--.*$', Comment.Single),

            (r'(?i)(\d*\.\d+|\d+\.\d*)(e[+-]?\d+)?', Number.Float),
            (r'(?i)\d+e[+-]?\d+', Number.Float),
            ('(?i)0x[0-9a-f]*', Number.Hex),
            (r'\d+', Number.Integer),

            (r'\n', Text),
            (r'[^\S\n]', Text),
            # multiline strings
            (r'(?s)\[(=*)\[.*?\]\1\]', String),

            (r'(==|~=|<=|>=|\.\.\.|\.\.|[=+\-*/%^<>#@])', Operator),
            (r'[\[\]{}().,:;]', Punctuation),
            (r'(and|or|not)\b', Operator.Word),

            # Lua keywords
            ('(break|do|else|elseif|end|for|if|in|repeat|return|then|until|'
             r'while)\b', Keyword),
            # Terra keywords
            (r'(import)\b', Keyword),
            # Regent keywords
            ('(aliased|atomic|copy|cross_product|disjoint|dynamic_cast|'
             'exclusive|equal|fill|image|isnull|ispace|max|min|new|null|'
             'partition|preimage|product|reads|reduces|relaxed|region|'
             r'simultaneous|static_cast|where|writes)\b', Keyword),
            (r'(local|var)\b', Keyword.Declaration),
            (r'(true|false|nil)\b', Keyword.Constant),

            (r'(function|fspace|task|terra|struct)\b', Keyword, 'funcname'),

            (r'[A-Za-z_]\w*(\.[A-Za-z_]\w*)?', Name),

            ("'", String.Single, combined('stringescape', 'sqs')),
            ('"', String.Double, combined('stringescape', 'dqs'))
        ],

        'funcname': [
            (r'\s+', Text),
            ('(?:([A-Za-z_]\w*)(\.))?([A-Za-z_]\w*)',
             bygroups(Name.Class, Punctuation, Name.Function), '#pop'),
            # inline function
            ('\(', Punctuation, '#pop'),
        ],

        # if I understand correctly, every character is valid in a lua string,
        # so this state is only for later corrections
        'string': [
            ('.', String)
        ],

        'stringescape': [
            (r'''\\([abfnrtv\\"']|\d{1,3})''', String.Escape)
        ],

        'sqs': [
            ("'", String, '#pop'),
            include('string')
        ],

        'dqs': [
            ('"', String, '#pop'),
            include('string')
        ]
    }
