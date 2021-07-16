#!/usr/bin/env python3
#
# Copyright (c) 2020 BedRock Systems, Inc.
# This software is distributed under the terms of the BedRock Open-Source License.
# See the LICENSE-BedRock file in the repository root for details.
#

# TODO: Fix the following 5 fields
# General information about the project.
project = 'BedRock FM: CPP2V Foundations'
copyright = '2020 BedRock Systems'
author = 'Jasper Haag'

version = "0.0.1"
release = "alpha"

# -*- coding: utf-8 -*-
#
# Configuration file for the Sphinx documentation builder.
#
# This file does only contain a selection of the most common options. For a
# full list see the documentation:
# http://www.sphinx-doc.org/en/master/config

# NOTE: This configuration is based on coq/doc/sphinx/conf.py, since we utilize
#       coqrst (and the custom coq documentation setup) in order to create our
#       own documentation.

# NOTE: Be sure to read coq/doc/README.md if you encounter issues

# -- Path setup --------------------------------------------------------------

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.

import sys
import os
import sphinx

# Increase recursion limit for sphinx
sys.setrecursionlimit(10000)

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.
sys.path.append(os.path.abspath('../../alectryon/'))

# -- Prolog ------------------------------------------------------------------

# Include substitution definitions in all files
# TODO: Determine if/what we want in our preamble. A lot of this is coq-specific
#       so it may make sense to leave this part off for now
# with open(os.pat.abspath('../coq/doc/sphinx/refman-preamble.rst')) as s:
#     rst_prolog = s.read()

# -- General configuration ---------------------------------------------------

# If your documentation needs a minimal Sphinx version, state it here.
needs_sphinx = '2.3.1'

sertop_args = []
coqpaths = os.environ.get("COQPATH", "").split(':')
for coqpath in coqpaths:
    # NOTE: These are the suffixes for where the cpp2v-core and cpp2v artifacts
    #       are installed in CI
    if coqpath.strip() == '':
        continue
    sertop_args.extend(["-Q", coqpath + ","])

import alectryon.docutils

alectryon.docutils.LONG_LINE_THRESHOLD = 90
alectryon.docutils.CACHE_DIRECTORY = os.path.abspath("cache/")

# NOTE: Clément resolved the sphinx docinfo issue, but we still need to grab the
#       paths for bedrock to feed to SerAPI, so we're still using this.
alectryon.docutils.AlectryonTransform.SERTOP_ARGS = sertop_args

# NOTE: Add in other entries here if we want to register coqdoc things which are
#       compatible with the `:coqid:` role.
alectryon.docutils.COQ_IDENT_DB_URLS.append(
    ("bedrock", "https://bedrocksystems.gitlab.io/cpp2v/$modpath.html#$ident")
)

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom
# ones.
extensions = [
    # This could be useful for delineating cpp2v-core and cpp2v
    'sphinx.ext.ifconfig',

    # NOTE: These are included for completeness, but it's not clear that
    #       we'll actually be using them
    'sphinx.ext.mathjax',
    'sphinx.ext.todo',

    # NOTE: These are the key extensions which enables our documentation efforts
    'alectryon.sphinx'
    # 'coqrst.coqdomain'
]

# NOTE: This may not be as important in the fm-docs repo, but it's probably
#       useful when we enforce more thorough documentation standards in
#       cpp2v(-core)
report_undocumented_coq_objects = "warning"

# Add any paths that contain templates here, relative to this directory.
templates_path = ['_templates']

# The suffix(es) of source filenames.
# You can specify multiple suffix as a list of string:
#
# source_suffix = ['.rst', '.md']
source_suffix = '.rst'

# The master toctree document.
master_doc = 'index'

# The language for content autogenerated by Sphinx. Refer to documentation
# for a list of supported languages.
#
# This is also used if you do content translation via gettext catalogs.
# Usually you set "language" from the command line for these cases.
language = None

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This pattern also affects html_static_path and html_extra_path.
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store', 'orphans/*.rst', '**/private/*.rst']

# The reST default role (used for this markup: `text`) to use for all
# documents.
default_role = 'coq'

# Use the Coq domain
# primary_domain = 'coq'

# If true, '()' will be appended to :func: etc. cross-reference text.
#add_function_parentheses = True

# If true, the current module name will be prepended to all description
# unit titles (such as .. function::).
#add_module_names = True

# If true, sectionauthor and moduleauthor directives will be shown in the
# output. They are ignored by default.
#show_authors = False

# The name of the Pygments (syntax highlighting) style to use.
#pygments_style = 'sphinx'
#highlight_language = 'text'
#suppress_warnings = ["misc.highlighting_failure"]

# A list of ignored prefixes for module index sorting.
#modindex_common_prefix = []

# If true, keep warnings as "system message" paragraphs in the built documents.
#keep_warnings = False

# If true, `todo` and `todoList` produce output, else they produce nothing.
todo_include_todos = False

# Extra warnings, including undefined references
nitpicky = True

nitpick_ignore = [ ('token', token) for token in [
    'binders',
    'collection',
    'modpath',
    'tactic',
]]

# -- Options for HTML output -------------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
#
html_theme = 'sphinx_rtd_theme'
# html_theme = 'agogo'
# html_theme = 'alabaster'
# html_theme = 'haiku'
# html_theme = 'bizstyle'

# Theme options are theme-specific and customize the look and feel of a theme
# further.  For a list of options available for each theme, see the
# documentation.
#
html_theme_options = {
    'prev_next_buttons_location': 'bottom',
#    'gitlab_url': 'https://gitlab.com/bedrocksystems/formal-methods/fm-docs',
    'style_external_links': True
}

# Add any paths that contain custom themes here, relative to this directory.
#import sphinx_rtd_theme
#html_theme_path = [sphinx_rtd_theme.get_html_theme_path()]

# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".
html_static_path = ['_static', '../../alectryon/alectryon/assets']

html_css_files = [
    'css/justify.css',
]

# Custom sidebar templates, must be a dictionary that maps document names
# to template names.
#
# The default sidebars (for documents that don't match any pattern) are
# defined by theme itself.  Builtin themes are using these templates by
# default: ``['localtoc.html', 'relations.html', 'sourcelink.html',
# 'searchbox.html']``.
#
# html_sidebars = {}


# -- Options for HTMLHelp output ---------------------------------------------

# Output file base name for HTML help builder.
htmlhelp_basename = 'cpp2v-foundations-doc'


# -- Options for LaTeX output ------------------------------------------------

latex_elements = {
    # The paper size ('letterpaper' or 'a4paper').
    #
    # 'papersize': 'letterpaper',

    # The font size ('10pt', '11pt' or '12pt').
    #
    # 'pointsize': '10pt',

    # Additional stuff for the LaTeX preamble.
    #
    # 'preamble': '',

    # Latex figure (float) alignment
    #
    # 'figure_align': 'htbp',
}

# Grouping the document tree into LaTeX files. List of tuples
# (source start file, target name, title,
#  author, documentclass [howto, manual, or own class]).
latex_documents = [
    (master_doc, 'pragmaticFM.tex', 'BedRock FM: A Pragmatic Guide',
     'Jasper Haag', 'manual'),
]


# -- Options for manual page output ------------------------------------------

# One entry per manual page. List of tuples
# (source start file, name, description, authors, manual section).
man_pages = [
    (master_doc, 'pragmaticfm', 'BedRock FM: A Pragmatic Guide',
     [author], 1)
]


# -- Options for Texinfo output ----------------------------------------------

# Grouping the document tree into Texinfo files. List of tuples
# (source start file, target name, title, author,
#  dir menu entry, description, category)
texinfo_documents = [
    (master_doc, 'PragmaticFMDocumentation', 'BedRock FM: A Pragmatic Guide',
     author, 'PragmaticFMDocumentation', 'A pragmatic guide to formal methods within BedRock.',
     'Miscellaneous'),
]


# -- Options for Epub output -------------------------------------------------

# Bibliographic Dublin Core info.
epub_title = project

# The unique identifier of the text. This can be a ISBN number
# or the project homepage.
#
# epub_identifier = ''

# A unique identification for the text.
#
# epub_uid = ''

# A list of files that should not be packed into the epub file.
epub_exclude_files = ['search.html']
