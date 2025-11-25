""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" ftplugin/tex/tex-labels.vim - LaTeX reference completion popup
" 	Provides popup menu for \ref, \eqref, \pageref, and \cite commands
"
" Maintainer:   Bin Zhou   <zhoub@bnu.edu.cn>
" Version:      1.1.0
"
" Upgraded on: Tue 2025-11-25 19:20:36 CST (+0800)
" Last change: Tue 2025-11-25 22:43:12 CST (+0800)
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
"	Configuration variables
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Only load once per buffer
if exists('b:loaded_tex_labels')
  finish
endif
let b:loaded_tex_labels = 1

" Configuration options

" Background color of popup windows (default: 'LightYellow')
if !exists('g:tex_labels_popup_bg')
  let g:tex_labels_popup_bg = 'LightYellow'
endif

" Height of popup windows (default: 8)
if !exists('g:tex_labels_popup_height')
  let g:tex_labels_popup_height = 8
endif

" Maximum number of labels to display
" (default: 4 times of g:tex_labels_popup_height)
if !exists('g:tex_labels_limit')
    let g:tex_labels_limit = 4 * g:tex_labels_popup_height
elseif g:tex_labels_limit < max([g:tex_labels_popup_height, 8])
    let g:tex_labels_limit = max([g:tex_labels_popup_height, 8])
endif

" Searching for '%! Main file: ...' only in the top
" {g:tex_labels_mainfile_scope} lines of the current file.
" (default: 16)
if !exists('g:tex_labels_mainfile_scope')
    let g:tex_labels_mainfile_scope = 16
endif

" Which are file paths relative to (default: 'CFD')
if !exists('g:tex_labels_path_WRT')
    " 'CFD': relative to directory of current file
    " 'PWD': relative to current working directory
    " 'MFD': relative to directory of the main file
    let g:tex_labels_path_WRT = 'CFD'
endif


" Counter for s:Popup_CheckLabels()
if !exists('g:tex_labels_check_length') || g:tex_labels_check_length < 1
    let g:tex_labels_check_length = 3
endif
let b:tex_labels_counter = 0

" Whether there are too many labels
let b:tex_labels_item_overflow = 0


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
"	Fundamental functions
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Function returning a List with repeated items in {list} removed.
" Note that uniq() removes adjacent repeated items only.
function! s:RemoveDuplicates(list)
    if empty(a:list)
	return a:list
    endif

    let l:clean_list = []
    for l:item in a:list
	if index(l:clean_list, l:item) == -1
	    call add(l:clean_list, l:item)
	endif
    endfor

    return l:clean_list
endfunction

function! On_Windows()
    return has("win64") || has("win32") || has("win95") || has("win16")
endfunction

" Function to check if {path} is absolute
function! s:IsAbsolutePath(path)
    let l:path = trim(a:path)
    if empty(l:path)
        return 0
    endif

    " Windows systems: Path starts with drive letter (e.g., C:\ or D:/)
    if On_Windows()
        return l:path =~# '^[a-zA-Z]:[\\/]'
    endif

    " Unix-like systems: Path starts with /
    return l:path =~ '^/'
endfunction

" Function to obtain the absolute path of {filename}, with respect to {supfile}
" if it presents.
" call s:GetAbsolutePath(filename [, supfile])
"   {filename}		file name of one to return its absolute path
"   {supfile}		when present, relative path of {filename} is with
"			respec to it
function! s:GetAbsolutePath(filename, ...)
    if trim(a:filename) == "%"
	let l:path = expand("%:p")
    else
	let l:path = expand(trim(a:filename))
    endif


    if s:IsAbsolutePath(l:path)
	return simplify(l:path)
    endif

    if a:0 > 0 && !empty(trim(a:1))
	if trim(a:1) == "%"
	    let l:relative = expand("%:p")
	else
	    let l:relative = expand(trim(a:1))
	endif
    else
	let l:relative = expand("%:p")
    endif

    " relative path calculated:
    let l:path = fnamemodify(l:relative, ":p:h") ..
		\ (On_Windows() ? "\\" : "/") .. l:path
    return simplify(l:path)
endfunction

" Function to get the environment variable initialed with '$' or '%'
" If an environment variable is embedded into another environment variable,
" this function cannot get it.
"
" In fact, latex does not support most of shell environment variables.
" Obsolete.
function! s:PopEnvironmentVariable(path)
    let l:path = trim(a:path)

    if empty(l:path)
	return ''
    endif

    if On_Windows()
	let l:env_var = matchstr(l:path, '^%[a-zA-Z_][a-zA-Z0-9_]*%')
	if len(l:env_var) > 2
	    return l:env_var
	endif
    endif

    let l:env_var = matchstr(l:path, '^\$[a-zA-Z_][a-zA-Z0-9_]*')
    if len(l:env_var) > 1
	return l:env_var
    endif

    let l:env_var = matchstr(l:path, '^\${[a-zA-Z_][a-zA-Z0-9_]*}')
    if len(l:env_var) > 3
	return l:env_var
    endif

    let l:env_var = matchstr(l:path, '^\${[a-zA-Z_][a-zA-Z0-9_]*\s*:.*}')
    if len(l:env_var) > 5
	return l:env_var
    endif

    return ''
endfunction

" Function to get relative path from a given path.  Usage:
"   call s:GetRelativePath(path [, base_path])
" Parameters:
"   {path}	the path to convert (must be an absolute path)
"   {base}	the base path to calculate relative to (can be relative
"		or absolute, defaults to current working directory)
" Returns:
"   Relative path from {base_path} to {path}, or absolute path in some
"   extraordinary situation.
function! s:GetRelativePath(path, ...)
    let l:abs_path = trim(a:path)

    " Validate input parameters
    if empty(l:abs_path)
	" DEBUGGING:
        echohl ErrorMsg
        echo "Error: Absolute path must be provided"
        echohl None

        return ''
    endif

    if a:0 > 0 && !empty(trim(a:1))
	if trim(a:1) == '%:p:h' || trim(a:1) == '%:p' || trim(a:1) == '%'
	    let l:base_abs = expand("%:p:h")
	else
	    let l:base_abs = simplify(fnamemodify(trim(a:1), ':p'))
	endif
    else
	" If no base path provided, define l:base_abs according to the value
	" of g:tex_labels_path_WRT .
	if g:tex_labels_path_WRT == 'MFD' && !empty(b:tex_labels_MainFile)
	    let l:base_abs = fnamemodify(b:tex_labels_MainFile, ":p:h")
	elseif g:tex_labels_path_WRT == 'PWD'
	    let l:base_abs = fnamemodify($PWD, ":p")
	else
	    let l:base_abs = getcwd()
	endif
    endif

    " Get normalized absolute paths (resolve symlinks and convert to full path
    " format)
    let l:absolute = simplify(fnamemodify(l:abs_path, ':p'))

    " If paths are the same, return current directory
    if l:absolute == l:base_abs
        return '.'
    endif

    " Check if running on Windows to handle path separators correctly
    let l:is_windows = On_Windows()

    " Handle path separators (Windows uses backslash, other systems use forward
    " slash)
    if l:is_windows
	let l:abs_parts = split(l:absolute, '(/|\\)+', 1)
	let l:base_parts = split(l:base_abs, '(/|\\)+', 1)
    else
	let l:abs_parts = split(l:absolute, '/')
	let l:base_parts = split(l:base_abs, '/')
    endif

    " Remove empty string elements (handle leading separators)
    let l:abs_parts = filter(l:abs_parts, '!empty(v:val)')
    let l:base_parts = filter(l:base_parts, '!empty(v:val)')

    if len(l:abs_parts) == 0 && len(l:base_parts) == 0
	return l:absolute
    elseif l:abs_parts[0] != l:base_parts[0]
	return l:absolute
    endif

    " Find the longest common prefix
    let l:common_len = 0
    let l:max_len = min([len(l:abs_parts), len(l:base_parts)])

    while l:common_len < l:max_len &&
		\ l:abs_parts[l:common_len] == l:base_parts[l:common_len]
        let l:common_len += 1
    endwhile
    " It is sure that l:common_len > 0.

    " Build relative path parts
    let l:relative_parts = []

    " Add upward path parts (from base path to common prefix)
    " Number of '..'s: len(l:base_parts) - l:common_len
    let l:num_updirs = len(l:base_parts) - l:common_len
    if l:num_updirs > 3
	return l:absolute
    endif

    if l:num_updirs > 0
	for i in range(l:num_updirs)
	    call add(l:relative_parts, '..')
	endfor
    endif

    " Add downward path parts (from common prefix to target path)
    let l:num_dirs = len(l:abs_parts) - l:common_len
    if l:num_dirs == 0 && l:num_updirs == 0
	" Normally this won't happen, because it has been tested by
	" 'l:absolute == l:base_abs'.
	return '.'
    elseif l:num_dirs > 0
	for i in range(l:common_len, len(l:abs_parts) - 1)
	    call add(l:relative_parts, l:abs_parts[i])
	endfor
    endif

    " Join path parts
    let l:relative_path = join(l:relative_parts, (l:is_windows ? '\' : '/'))

    return l:relative_path
endfunction

" Simplified version: Get relative path to current working directory
" Parameters:
"   absolute_path: The absolute path to convert
" Returns:
"   Relative path from current working directory to absolute_path
function! GetRelativeToCwd(absolute_path) abort
    if empty(a:absolute_path)
        echohl ErrorMsg
        echo "Error: Absolute path not provided"
        echohl None

        return ''
    endif

    " Use Vim's built-in filename modifiers to get relative path
    " :~ means relative to home directory (optional)
    " :. means relative to current directory
    return fnamemodify(a:absolute_path, ':~:.')
endfunction


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
"	Fundamental functions related to TeX/LaTeX files
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Function returning a string with TeX comments removed from the string {text}.
function! s:RemoveTeXComment(text)
    let l:index = stridx(a:text, '%')
    if l:index == 0
	return ""
    elseif l:index < 0
	return a:text
    endif

    " Now there is '%' in {text} somewhere not in the beginning:
    while l:index > 0
	if  strpart(a:text, l:index - 1, 1) != '\'
	    return strpart(a:text, 0, l:index)
	else
	    let l:index = stridx(a:text, '%', l:index + 1)
	endif
    endwhile

    return a:text
endfunction

" Function to match curly braces.  Note that '\{' and '\}' are ignored.
"	s:MatchCurlyBrace(text [, start])
"   {text}	string
"   {start}	offset where the search begins
function! s:MatchCurlyBrace(text, ...)
    let l:positions = []
    let l:text_len = len(a:text)

    if a:0 > 0
	let l:start = a:1
    else
	let l:start = 0
    endif

    if l:start >= l:text_len - 1
	" Starting position is so far away that no '}' can be found.
	return l:positions
    endif

    while 1
	let l:left_ind = match(a:text, '{', l:start)

	if l:left_ind < 0 || l:left_ind == l:text_len - 1
	    " No '{' found, or no '}' at all.
	    return l:positions
	elseif strpart(a:text, l:left_ind - 1, 1) == '\'
	    " '\{' is found, which is ignored.
	    let l:start = l:left_ind + 1
	    continue
	else
	    " Now '{' but not '\{' is found.
	    break
	endif
    endwhile

    " The first '{' has been found, not at the end.  That is,
    "		l:left_ind <= l:text_len -2 .
    let l:level = 0
    let l:right_ind = -1
    for i in range(l:left_ind + 1, l:text_len - 1)
	let l:char = strpart(a:text, i, 1)
	if l:char == '}' && strpart(a:text, i - 1, 1) != '\'
	    if l:level == 0
		let l:right_ind = i
		break
	    else
		let l:level -= 1
	    endif
	elseif l:char == '{' && strpart(a:text, i - 1, 1) != '\'
	    let l:level += 1
	endif
    endfor

    if l:right_ind < 0
	return l:positions
    else
	call extend(l:positions, [l:left_ind, l:right_ind])
	return l:positions
    endif
endfunction

" Function to locate '{', which is not part of '\{', in the string {expr}
" with the greatest offset that is less than {curr_offset}
function! s:SearchOpenBrace_left(expr, curr_offset)
    if empty(a:expr) || a:curr_offset <= 0
	return -1
    endif

    let l:length = min([len(a:expr), a:curr_offset])
    " Then {l:length} >= 1

    while l:length > 0
	let l:offset = strridx( strpart(a:expr, 0, l:length), '{' )
	if l:offset <= 0
	    " '{' not found, or at the beginning of {expr}
	    return l:offset
	endif

	" Then {l:offset} >= 1

	if strpart(a:expr, l:offset - 1, 1) != '\'
	    return l:offset
	elseif l:offset == 1
	    " Only a single '\{' is found.
	    return -1
	else
	    " {l:offset} >= 2
	    let l:length = l:offset - 1
	endif
    endwhile

    " Not found.
    return -1
endfunction


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
"	Fundamental functions and related buffer parameters for this plugin
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Function to find main file specification.
" At most one main file supported.
function! s:FindMainFile(filename)
    if !filereadable(a:filename)
        return ''
    endif

    let l:lines = readfile(a:filename, '', g:tex_labels_mainfile_scope)
    if empty(l:lines)
        return ''
    endif

    let l:line_num = len(l:lines)

    for i in range(l:line_num)
        let l:line = l:lines[i]
        let l:matches = matchlist(l:line, '%! Main file:[ \t]*\([^ \t\n\r]*\)')
        if len(l:matches) > 1
            let l:main_file = l:matches[1]
	    if empty(l:main_file)
		continue
	    else
		return s:GetAbsolutePath(l:main_file, a:filename)
	    endif
        endif
    endfor

    " Maybe {filename} should be returned instead?
    return ''
endfunction

" File name of the main LaTeX file
" Maybe always updated?
if !exists('b:tex_labels_MainFile')
    let b:tex_labels_MainFile = s:FindMainFile(expand("%:p"))
endif

" Function to obtain the name of auxiliary file
"   {type}	"aux", "subf", "supf", "label", "bibitem" or "tag"
function! s:AuxFileName(filename, type)
    if empty(a:filename)
	return ''
    elseif a:type != "aux" && a:type != "subf" && a:type != "supf" &&
		\ a:type != "label" && a:type != "bibitem" && a:type != "tag"
	return ''
    endif

    if a:filename =~ '\.tex$'
	return substitute(a:filename, 'tex$', a:type, '')
    else
	return a:filename .. '.' .. a:type
    endif
endfunction

" Function to find included/input files recursively
"   s:FindSubFiles(file, recursively)
"   {recursively}	to trigger a recursive search.
function! s:FindSubFiles(file, ...)
    let l:subfiles = []
    let l:file = s:GetAbsolutePath(a:file)
    let l:current_file = expand("%:p")

    if !filereadable(l:file)
        return l:subfiles
    endif

    if l:file ==# l:current_file && &modified
	" {l:file} is the current file and is modified:
	let l:lines_read = getbufline('%', 1, '$')
    elseif has("win64") || has("win32")
	let l:lines_read = readfile(l:file)
    else
	let l:lines_read = systemlist('grep \include{ ' .. shellescape(l:file))
	let l:lines_read = extend(l:lines_read,
		    \ systemlist('grep \input{ ' .. shellescape(l:file))
		    \ )
    endif

    if empty(l:lines_read)
        return l:subfiles
    endif

    for line in l:lines_read
        " Remove comments
        let l:clean_line = s:RemoveTeXComment(line)

        " Check for \include and \input
        for cmd in ['include', 'input']
	    let l:start = match(l:clean_line, '\\' .. cmd)
	    if l:start < 0
		continue
	    endif

	    let l:curlybrace_at = s:MatchCurlyBrace(l:clean_line, l:start)
	    if !empty(l:curlybrace_at)
		let l:subfile = strpart(l:clean_line, l:curlybrace_at[0] + 1,
			    \ l:curlybrace_at[1] - l:curlybrace_at[0] - 1
			    \ )
                let l:subfile = trim(l:subfile)
		if empty(l:subfile)
		    continue
		endif

		if l:subfile !~ '\.tex$'
		    let l:subfile = l:subfile .. '.tex'
		endif
		if !empty(b:tex_labels_MainFile)
		    let l:subfile = s:GetAbsolutePath(l:subfile,
				\ b:tex_labels_MainFile)
		else
		    let l:main_file = s:FindMainFile(l:file)
		    if !empty(l:main_file)
			let b:tex_labels_MainFile = l:main_file
			let l:subfile = s:GetAbsolutePath(l:subfile,
				    \ l:main_file)
		    else
			let l:subfile = s:GetAbsolutePath(l:subfile, l:file)
		    endif
		endif

                call add(l:subfiles, l:subfile)

		if cmd == 'input'
		    let l:file_sup = s:AuxFileName(l:subfile, 'supf')
		    call writefile([l:file], l:file_sup)
		endif

                " Recursively find files in the included file
		if a:0 > 0
		    let l:sub_files = s:FindSubFiles(l:subfile, 1)
		    call extend(l:subfiles, l:sub_files)
		endif
            endif
        endfor
    endfor

    return s:RemoveDuplicates(l:subfiles)
endfunction

" Behaving like GNU make, the function
"   s:Update_SubFiles([filename])
" updates auxiliary files
"   substitute(filename, '\.tex$', '\.subf', '')
" and
"   substitute(filename, '\.tex$', '\.supf', '')
" when necessary.
" If {filename} is omitted or empty, its default value is
"	b:tex_labels_MainFile
" when it is nonempty; or
"	the current file
" provided that b:tex_labels_MainFile is empty.
function! s:Update_SubFiles(...)
    " Set the value of {filename}
    if a:0 > 0 && !empty(trim(a:1))
	let l:filename = s:GetAbsolutePath(trim(a:1))
    elseif !empty(b:tex_labels_MainFile)
	let l:filename = b:tex_labels_MainFile
    else
	let l:filename = expand("%:p")
    endif

    " DEBUGGING:
    if l:filename !~ '\.tex$'
        echohl ErrorMsg
	echo "s:Update_SubFiles: File name <" .. l:filename ..
		    \ "> without extension <.tex>?"
        echohl None

    elseif !filereadable(l:filename)
        echohl ErrorMsg
	echo "s:Update_SubFiles: file <" .. l:filename .. "> not readable."
	echo "s:Update_SubFiles stops."
        echohl None

	return -1
    endif

    " The file <xxx.subf> is in the same directory of <xxx.tex> or <xxx>.
    let l:target = s:AuxFileName(l:filename, 'subf')

    if empty(getfperm(l:target)) || getftime(l:filename) > getftime(l:target)
	let l:included_files = s:FindSubFiles(l:filename)
	call writefile(l:included_files, l:target)
    else
	let l:included_files = []
    endif

    let l:included_files = readfile(l:target)

    if empty(l:included_files)
	return 0
    endif

    for file in l:included_files
	if !empty(file) && s:Update_SubFiles(file) < 0
	    return -1
	endif
    endfor
    return 0
endfunction

" Function to get all relevant files to search.  Usage:
"   call s:GetFilesToSearch([main_file [, exclude_currentfile]])
"   {main_file}		the name of the file to search which files (called
"			subfiles) have been included (by \include) or input
"			(by \input) into it, or into its subfiles and subfiles
"			of subfiles...
"    {exclude_currentfile}
"			current file, its subfiles and subfiles of its subfiles,
"			are not search if {exclude_currentfile} == 1.
function! s:GetFilesToSearch(...)
    let l:current_file = expand("%:p")
    let l:files = []
    let l:roots = []

    if a:0 > 0 && !empty(trim(a:1))
	let l:main_file = s:GetAbsolutePath(a:1)
    elseif !empty(b:tex_labels_MainFile)
	let l:main_file = b:tex_labels_MainFile
    else
	let l:main_file = l:current_file
    endif
    " Now {l:main_file} is nonempty

    " The current file is included, if {a:2} == 1.
    if l:current_file != l:main_file && (a:0 <= 1 || (a:0 >= 2 && !a:2))
	call add(l:roots, l:current_file)
    endif

    if filereadable(l:main_file)
	call add(l:roots, l:main_file)
    endif

    if empty(l:roots)
	return l:files
    endif

    " Files included by searched files are also searched.
    for root_file in l:roots
	call add(l:files, root_file)

	if s:Update_SubFiles(root_file) < 0
	    continue
	endif

	let l:root_sub = s:AuxFileName(root_file, 'subf')
	if !filereadable(l:root_sub)
	    continue
	endif

	let l:included_files = readfile(l:root_sub)
	if !empty(l:included_files)
	    call extend(l:files, l:included_files)
	endif

	for file in l:included_files
	    let l:subsub_files = s:GetFilesToSearch(file, 1)
	    if !empty(l:subsub_files)
		call extend(l:files, l:subsub_files)
	    endif
	endfor
    endfor

    " Remove duplicates
    return s:RemoveDuplicates(l:files)
endfunction

" Function to extract labels and bibitems from a file, with
"   {type}		'label', 'bibitem' or 'tag'
" It does not search items in subfiles of {filename}.
function! s:ExtractLabelsBibitemsTags(filename, type)
    let l:items = []
    let l:eff_filename = trim(a:filename)
    let l:filename = s:GetAbsolutePath(l:eff_filename)
    let l:current_file = expand("%:p")

    if empty(l:eff_filename) || !filereadable(l:filename)
	return l:items
    endif

    let l:grep_called = 0
    if l:filename ==# l:current_file && &modified
	" {l:filename} is the current file and is modified:
	let l:lines = getbufline('%', 1, '$')
    elseif has("win64") || has("win32")
	let l:lines = readfile(l:filename)
    else
	let l:lines = systemlist('grep -n ''\\' .. a:type .. '.*{'' ' ..
		    \ shellescape(l:filename))
	let l:grep_called = 1
    endif

    if empty(l:lines)
	return l:items
    endif

    for i in range(len(l:lines))
        let l:line = l:lines[i]
        let l:line_num = i + 1

        " Remove comments
        let l:clean_line = s:RemoveTeXComment(l:line)
        if empty(l:clean_line)
            continue
        endif

        " Search commands \label, \bibitem or \tag
        let l:start = match(l:clean_line, '\\' .. a:type)
	if l:start < 0
	    continue
	endif

	let l:curlybrace_at = s:MatchCurlyBrace(l:clean_line, l:start)
	if !empty(l:curlybrace_at)
	    let l:label = strpart(l:clean_line, l:curlybrace_at[0] + 1,
			\ l:curlybrace_at[1] - l:curlybrace_at[0] - 1
			\ )

	    if l:grep_called
		let l:line_num = matchlist(l:clean_line, '^\([^:]*\):')
		let l:line_num = l:line_num[1]
	    else
		let l:line_num = i + 1
	    endif

            let l:item = {
			\ 'idcode': l:label,
			\ 'counter': a:type == 'label' ? '??' : a:type,
			\ 'idnum': '??',
			\ 'page': '??',
			\ 'line': l:line_num,
			\ 'file': fnamemodify(l:filename, ':t'),
			\ 'full_path': l:filename
			\ }
	    call add(l:items, l:item)
	endif
    endfor

    return l:items
endfunction

" Function to parse auxiliary file for numbering information.  Usage:
"   call s:ParseAuxFile(aux_file)
"   {aux_file}		a file name with extension ".aux"
function! s:ParseAuxFile(aux_file)
    let l:label_data = {}
    let l:bib_data = {}

    let l:aux_file = trim(a:aux_file)
    if empty(l:aux_file)
        return []
    endif

    while empty(getfperm(l:aux_file))
	let l:file_supf = substitute(l:aux_file, '.aux$', '.supf', '')
	if empty(getfperm(l:file_supf)) || !filereadable(l:file_supf)
	    return []
	endif

	let l:upper_file = readfile(l:file_supf)
	if len(l:upper_file) != 1 || empty( l:upper_file[0] )
	    return []
	else
	    let l:aux_file = s:AuxFileName(l:upper_file[0], "aux")
	endif
    endwhile

    if !filereadable(l:aux_file)
	return []
    endif

    let l:aux_lines = readfile(l:aux_file)
    if empty(l:aux_lines)
	return []
    endif

    for line in l:aux_lines
        " Parse \newlabel commands
	let l:start = match(line, '\\newlabel')
	if l:start >= 0
	    let l:curlybrace_at = s:MatchCurlyBrace(line, l:start)
	    if !empty(l:curlybrace_at)
		let l:label = strpart(line, l:curlybrace_at[0] + 1,
			    \ l:curlybrace_at[1] - l:curlybrace_at[0] - 1
			    \ )

		let l:start = l:curlybrace_at[1] + 2
		let l:curlybrace_at = s:MatchCurlyBrace(line, l:start)
		let l:num = strpart(line, l:curlybrace_at[0] + 1,
			    \ l:curlybrace_at[1] - l:curlybrace_at[0] - 1
			    \ )

		let l:start = l:curlybrace_at[1] + 1
		let l:matches = matchlist(line,
			    \ '{\([^}]*\)}{\([^}]*\)}{\([^\.]*\)\.', l:start)

		if len(l:matches) > 3
		    let l:page = l:matches[1]
		    let l:counter = l:matches[3]
		    let l:label_data[l:label] = {'counter': l:counter, 'idnum': l:num, 'page': l:page}
		endif
	    endif
	endif

        " Parse \bibcite commands
	let l:start = match(line, '\\bibcite')
	if l:start >= 0
	    let l:curlybrace_at = s:MatchCurlyBrace(line, l:start)
	    if !empty(l:curlybrace_at)
		let l:bibitem = strpart(line, l:curlybrace_at[0] + 1,
			    \ l:curlybrace_at[1] - l:curlybrace_at[0] - 1
			    \ )
		let l:start = l:curlybrace_at[1] + 1

		let l:matches = matchlist(line, '{\([^}]*\)}', l:start)
		if len(l:matches) > 1
		    let l:num = l:matches[1]
		    let l:bib_data[l:bibitem] = {'counter': 'bibitem', 'idnum': l:num, 'page': ''}
		endif
	    endif
        endif
    endfor

    return [l:label_data, l:bib_data]
endfunction


" Function to process selected file
function! s:CompleteLabelInfo(file, type)
    if a:type != "label" && a:type != "bibitem" && a:type != "tag"
        echohl ErrorMsg
	echo "s:CompleteLabelInfo: Unknown type " .. a:type .. "."
        echohl None

	return []
    endif

    let l:file = s:GetAbsolutePath(a:file)
    let b:tex_labels_item_overflow = 0
    let l:items = s:ExtractLabelsBibitemsTags(l:file, a:type)

    if empty(l:items)
	return l:items
    elseif b:tex_labels_item_overflow
	call remove(l:items, 0, -1)
	return []
    endif

    if a:type == "tag"
	return l:items
    endif

    " Parse auxiliary file for numbering
    let l:aux_file = fnamemodify(l:file, ':r') .. '.aux'
    let l:data_ParseAuxFile = s:ParseAuxFile(l:aux_file)

    if empty(l:data_ParseAuxFile)
	return l:items
    elseif a:type == 'label'
	let l:aux_data = l:data_ParseAuxFile[0]
    else
	let l:aux_data = l:data_ParseAuxFile[1]
    endif

    " Merge auxiliary data
    for item in l:items
        if has_key(l:aux_data, item.idcode)
            let item.idnum = l:aux_data[item.idcode].idnum
	    if a:type == "label"
		let item.counter = l:aux_data[item.idcode].counter
		let item.page = l:aux_data[item.idcode].page
	    endif
        endif
    endfor

    return l:items
endfunction

" Function to format menu item
"   {item}	a Dictionary in a List returned by
" 			s:CompleteLabelInfo(file, type)
" 		or
" 			s:ExtractLabelsBibitemsTags(file, type)
"   {type}	'label', 'bibitem' or 'tag'
function! s:FormatMenuItem(item, type)
    if empty(a:item)
	return ''
    endif

    if a:type == "label"
	return "(" .. a:item.counter .. ": " .. a:item.idnum .. ") {" ..
		    \ a:item.idcode .. "} {p." .. a:item.page ..
		    \ "} {l." .. a:item.line .. "} {file: " ..
		    \ a:item.full_path .. "}"

    elseif a:type == "bibitem"
	if a:item.counter != "bibitem"
	    echohl ErrorMsg
	    echo "s:FormatMenuItem: corrupted data.  Nothing returned."
	    echohl None

	    "return ''
	endif

	return "Ref. [" .. a:item.idnum .. "] {" ..
		    \ a:item.idcode .. "} {l." .. a:item.line ..
		    \ "} {file: " .. a:item.full_path .. "}"

    elseif a:type == "tag"
	if a:item.counter != "tag"
	    echohl ErrorMsg
	    echo "s:FormatMenuItem: corrupted data.  Nothing returned."
	    echohl None

	    return ''
	endif

	return "{tag: " .. a:item.idcode .. "} {l." ..
		    \ a:item.line .. "} {file: " ..  a:item.full_path .. "}"

    else
	echohl ErrorMsg
	echo "s:FormatMenuItem: Unknown type " .. a:type ..
		    \ ".  Nothing returned."
	echohl None

	return ''
    endif
endfunction

" Function to align displayed contents.
"   {data}	A List of strings returned from s:FormatMenuItem() .
"   {type}	'label', 'bibitem' or 'tag'
function! s:AlignMenuItem(data, type)
    let l:output = []
    let l:lengths = []
    let l:curly_braces = []

    if a:type != 'label' && a:type != 'bibitem' && a:type != 'tag'
        echohl ErrorMsg
	echo 's:AlignMenuItem: type "' .. a:type .. '" not supported.'
	echohl None

	return l:output
    endif

    if empty(a:data)
	return l:output
    endif
    let l:data_len = len(a:data)

    " The first round
    for i in range(l:data_len)
	let l:item = a:data[i]
	let l:brace_position = s:MatchCurlyBrace(l:item)
	if empty(l:brace_position)
	    return []
	endif

	call add(l:curly_braces, l:brace_position)

	if a:type == "label" || a:type == "bibitem"
	    call add(l:lengths, l:brace_position[0] - 1)
	else
	    call add(l:lengths, l:brace_position[1] + 1)

	    let l:brace_position = s:MatchCurlyBrace(l:item)
	    if empty(l:brace_position)
		return []
	    endif

	    let l:curly_braces[i] = l:brace_position
	endif
	call add(l:output, strpart(l:item, 0, l:lengths[i]))
    endfor

    if a:type == "label"
	let l:round_num = 4
    elseif a:type == "bibitem"
	let l:round_num = 3
    else
	let l:round_num = 2
    endif

    for r in range(l:round_num)
	let l:length_max = max(l:lengths)

	for i in range(l:data_len)
	    " Padding with spaces
	    let l:padding = " "
	    if l:length_max > l:lengths[i]
		for j in range(l:length_max - l:lengths[i])
		    let l:padding = l:padding .. " "
		endfor
	    endif
	    let l:output[i] = l:output[i] .. l:padding

	    let l:item = a:data[i]
	    let l:lengths[i] = l:curly_braces[i][1] - l:curly_braces[i][0] + 1
	    let l:output[i] = l:output[i] ..
			\ strpart(l:item, l:curly_braces[i][0], l:lengths[i])

	    if r < l:round_num - 1
		let l:brace_position = s:MatchCurlyBrace(l:item,
			    \ l:curly_braces[i][1])
		if empty(l:brace_position)
		    return []
		endif

		let l:curly_braces[i] = l:brace_position
	    endif
	endfor
    endfor

    return l:output
endfunction

" Function to replace filename with relative path
function! s:Refs_RelativePath(fomatted_line, type)
    if empty(a:fomatted_line)
	return ''
    endif

    if a:type == "label"
	let l:num_bracePairs = 4
    elseif a:type == "bibitem" || a:type == "tag"
	let l:num_bracePairs = 3
    else
        echohl ErrorMsg
	echo "s:Refs_RelativePath: type \"" .. a:type "\" not supported."
        echohl None

	return ''
    endif

    let l:positions = [-1, -1]
    for i in range(1, l:num_bracePairs)
	let l:positions = s:MatchCurlyBrace(a:fomatted_line, l:positions[1] + 1)
	if empty(l:positions)
	    echohl ErrorMsg
	    echo "s:Refs_RelativePath: incorrect format."
	    echohl None

	    return ''
	endif
    endfor

    if strpart(a:fomatted_line, l:positions[0],
		\ l:positions[1] - l:positions[0] + 1) !~ '^{file: '
	echohl ErrorMsg
	echo "s:Refs_RelativePath: incorrect format."
	echohl None

	return ''
    endif

    let l:full_path = strpart(a:fomatted_line, l:positions[0] + 7,
		\ l:positions[1] - l:positions[0] - 7)
    let l:ref = strpart(a:fomatted_line, 0, l:positions[0]) .. '{file: ' ..
		\ s:GetRelativePath(l:full_path) .. '}'
    return l:ref
endfunction

" Behaving like GNU make, the function
"	s:Update_AuxFiles([type [, filename]])
" updates auxiliary files <file.type> when {type} is given as "label", "bibitem"
" or "tag", and {file} is
"	substitute(filename, '\.tex$', '.' .. type, '')
" when {filename} is also given.
" When {filename} is omitted, each file (except for the current file)
" listed in the file
" 	substitute(b:tex_labels_MainFile, '\.tex$', '\.subf', '')
" is checked and updated, if necessary.
" When {type} is not given, either, files with extension ".label" and ".bibitem"
" are all updated, if necessary.
"
"   {type}	"label", "bibitem" or "tag"
function! s:Update_AuxFiles(...)
    let l:current_file = expand('%:p')
    let l:target_items = []
    let l:type = ''
    let l:status = 0

    if a:0 > 0 && !empty(trim(a:1))
	if a:1 != 'label' &&  a:1 != 'bibitem' && a:1 != 'tag'
	    echohl ErrorMsg
	    echo "s:Update_AuxFiles: type \'" .. a:1 ..
			\ "\' not supported.  Nothing done."
	    echohl None

	    return -1
	else
	    let l:type = trim(a:1)
	endif
    endif

    if a:0 >= 2 && !empty(l:type)
	if !empty(trim(a:2))
	    let l:filename = s:GetAbsolutePath(trim(a:2))
	    let l:type_file = s:AuxFileName(l:filename, l:type)
	    let l:file_aux = s:AuxFileName(l:filename, "aux")
	    let l:file_subf = s:AuxFileName(l:filename, "subf")
	    let l:file_supf = s:AuxFileName(l:filename, "supf")
	else
	    return s:Update_AuxFiles(l:type)
	endif

"	if getftype(a:2) == "link"
"	    let l:filename = resolve(a:2)
"	else
"	    let l:filename = a:2
"	endif
"
	if filereadable(l:file_supf)
	    let l:upper_file = readfile(l:file_supf)
	    if !empty(l:upper_file)
		call s:Update_AuxFiles(l:type, l:upper_file[0])
	    endif
	endif

	if filereadable(l:filename) && (
		    \ empty(getfperm(l:type_file)) ||
		    \ getftime(l:filename) > getftime(l:type_file) ||
		    \ getftime(l:file_aux) > getftime(l:type_file) ||
		    \ getftime(l:file_subf) > getftime(l:type_file)
		    \ )
	    if s:Update_SubFiles(l:filename) < 0
		return -1
	    endif

	    let l:info_items = s:CompleteLabelInfo(l:filename, l:type)
	    if len(l:info_items) > 0
		for item in l:info_items
		    call add(l:target_items, s:FormatMenuItem(item, l:type))
		endfor
	    endif

	    return writefile(l:target_items, l:type_file)
	endif

	return 0

    elseif a:0 >= 2 && empty(l:type)
	for each_type in ["label", "bibitem", "tag"]
	    if s:Update_AuxFiles(each_type, a:2) < 0
		let l:status = -1
	    endif
	endfor

	return l:status

    elseif a:0 == 1 && !empty(l:type)
	call s:Update_SubFiles()

	if !empty(b:tex_labels_MainFile)
	    let l:main_file = b:tex_labels_MainFile
	else
	    let l:main_file = l:current_file
	endif

	let l:searched_files = s:GetFilesToSearch(l:main_file)

	for file in l:searched_files
	    " Auxiliary files related to the current file are not updated:
	    "if fnamemodify(file, ':p') == l:current_file
	"	continue
	    "endif

	    if s:Update_AuxFiles(l:type, file) < 0
		let l:status = -1
	    endif
	endfor

	return l:status

    else
	for each_type in ["label", "bibitem", "tag"]
	    if s:Update_AuxFiles(each_type) < 0
		let l:status = -1
	    endif
	endfor

	return l:status
    endif
endfunction

" Function to get all relevant files containing \label, \bibitem or \tag
"   s:GetFilesContainingCommand({type} [, {mainfile}])
"   {type}	either "label", "bibitem" or "tag"
function! s:GetFilesContainingCommand(type, ...)
    if a:type != "label" && a:type != "bibitem" && a:type != "tag"
	echohl ErrorMsg
	echo 's:GetFilesContainingCommand: unknown type "' .. a:type .. '"'
	echohl None

	return -1
    endif

    if a:0 > 0
	let l:mainfile = a:1
	if s:Update_AuxFiles(a:type, l:mainfile) < 0
	    echohl ErrorMsg
	    echo 's:GetFilesContainingCommand: error form s:Update_AuxFiles'
	    echohl None

	    return -1
	endif

    else
	let l:mainfile = ''
	if s:Update_AuxFiles(a:type) < 0
	    echohl ErrorMsg
	    echo 's:GetFilesContainingCommand: error form s:Update_AuxFiles'
	    echohl None

	    return -1
	endif
    endif


    let l:effective_files = []
    let b:tex_labels_item_overflow = 0
    if empty(l:mainfile)
	let l:files = s:GetFilesToSearch()
    else
	let l:files = s:GetFilesToSearch(l:mainfile)
    endif

    for file in l:files
	let l:aux_file = s:AuxFileName(file, a:type)

	if getfsize(l:aux_file) > 0 || getfsize(l:aux_file) == -2
	    call add(l:effective_files, file)
	endif
    endfor

    return l:effective_files
endfunction

" Function to check whether there are, in the file {filename}, labels related to
" the LaTeX counter {counter_name}, returning 1 or 0 for "yes" or "no".
"
" If {filename} is the current file, contents in the buffer are not checked.
function! s:HasCounterLabels(filename, counter_name)
    if empty(a:filename) || empty(a:counter_name)
	return 0
    endif

    let l:file = s:GetAbsolutePath(a:filename)
    let l:aux_file = s:AuxFileName(l:file, "label")
    if !filereadable(l:aux_file)
	return 0
    endif

    let l:labels = readfile(l:aux_file)
    if empty(l:labels)
	return 0
    endif

    for item in l:labels
	let l:matched = matchlist(item, '^(\([^:]*\):.*)')
	if len(l:matched) < 2
	    continue
	endif

	if a:counter_name == l:matched[1]
	    return 1
	endif
    endfor

    return 0
endfunction

" Function to generate a List for \ref , \eqref , \pageref , \cite ,
" \label , \bibitem or \tag
"   {type}	"label", "bibitem" or "tag"
function! s:GetRefItems(filename, type)
    if a:type != "label" && a:type != "bibitem" && a:type != "tag"
	echohl ErrorMsg
	echo "s:GetRefItems: unknown type \"" .. a:type .. "\""
	echohl None

	return []
    endif

    let l:filename = s:GetAbsolutePath(a:filename)
    let l:current_file = expand('%:p')

    let l:aux_file = s:AuxFileName(l:filename, a:type)

    let l:refs = []
    if l:filename == l:current_file && &modified
	let l:items = s:CompleteLabelInfo(l:filename, a:type)

	if empty(l:items)
	    return l:refs
	endif

	for i in l:items
	    let l:ref_item = s:FormatMenuItem(i, a:type)
	    call add(l:refs, l:ref_item)
	endfor

	return l:refs

    elseif !filereadable(l:aux_file)
	return l:refs
    else
	call s:Update_AuxFiles(a:type, l:filename)
	let l:refs = readfile(l:aux_file)
	return l:refs
    endif
endfunction

" Get all references from current buffer and {b:tex_labels_MainFile}, if
" nonempty and readable, and from file recursively included/input from these
" files.
"   {limit}	If {limit} is a positive integer, s:GetAllReferences() stops
"		when the number of items is greater than {limit}, with an empty
"		List returned.  If {limit} is zero, s:GetAllReferences() finds
"		all reference items of type {type}, with a List containing all
"		these items returned.
"   {type}	"label", "bibitem" or "tag"
"
function! s:GetAllReferences(type, limit)
    if a:type != "label" && a:type != "bibitem" && a:type != "tag"
	echohl ErrorMsg
	echo 's:GetAllReferences: unknown type "' .. a:type .. '".'
	echohl None

	return []
    endif

    let l:refs = []
    let l:files = s:GetFilesToSearch()

    for file in l:files
	call extend(l:refs, s:GetRefItems(file, a:type))
	if a:limit > 0 && len(l:refs) > a:limit
	    call remove(l:refs, 0, -1)
	    let b:tex_labels_item_overflow = 1
	    return l:refs
	endif
    endfor

    return l:refs
endfunction

" Function to get all LaTeX counters related to \label{}.  Usage:
"   s:GetAllCounters([filename])
function! s:GetAllCounters(...)
    if a:0 > 0 && !empty(a:1)
	let l:refs = s:GetRefItems(a:1, "label")
    else
	let l:refs = s:GetAllReferences("label", 0)
    endif

    if empty(l:refs)
	return []
    endif

    let l:counters = []
    for item in l:refs
	if empty(item)
	    continue
	endif

	let l:counter_name = matchlist(item, '^(\([^:]*\):.*)')
	if !empty(l:counter_name) && !empty(l:counter_name[1])
	    call add(l:counters, l:counter_name[1])
	endif
    endfor

    let l:counters = s:RemoveDuplicates(l:counters)
    if empty(l:counters)
	return []
    else
	return sort(l:counters)
    endif
endfunction

function! s:GetLineNumber(ref)
    if empty(a:ref)
	return -1
    endif

    let l:line_num = matchstr(a:ref, '{line: \([0-9]*\)}')
    return l:line_num
endfunction

function! s:GetFileName(ref)
    if empty(a:ref)
	return ''
    endif

    let l:file_name = matchstr(a:ref, '{file: \([^}]*\)}')
    return l:file_name
endfunction


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
"	Functions and related buffer parameters for popup windows
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Current popup ID (buffer-local)
let b:tex_labels_popup = -1


" Clean up popup when leaving buffer
function! s:CleanupPopup()
  if b:tex_labels_popup != -1
    call popup_close(b:tex_labels_popup)
    let b:tex_labels_popup = -1
  endif
endfunction

" Popup filter function when no labels found
function! s:PopupFilter_void(winid, key)
    " Close popup on any other key
    "let b:tex_labels_popup = -1
    call popup_close(a:winid)
    return 1
endfunction

" Function showing a warning message
function! s:ShowWarningMessage(message)
    let l:text = []
    call add(l:text, a:message)
    call add(l:text, "")
    call add(l:text, "Press any key to close this window.")

    let l:popup_config = {
		\ 'line': winline() + 1,
		\ 'col': wincol(),
		\ 'pos': 'topleft',
		\ 'maxheight': 4,
		\ 'maxwidth': winwidth(0) - 8,
		\ 'highlight': 'TexLabelsPopup',
		\ 'border': [1, 1, 1, 1],
		\ 'borderhighlight': ['TexLabelsPopupBorder'],
		\ 'title': ' Warning ',
		\ 'titlehighlight': 'TexLabelsPopupTitle',
		"\ 'cursorline': 1,
		\ 'zindex': 200,
		\ 'filter': function('s:PopupFilter_void')
		\ }
    call popup_create(l:text, l:popup_config)
endfunction

" Function to process some keys for popup filters
function! s:Popup_KeyAction(winid, key, ...)
    " Store previous key for gg detection
    if !exists('b:prev_popup_key')
        let b:prev_popup_key = ''
    endif

    " Store a digital number for repeated command
    if !exists('b:count')
	let b:count = ""
    endif

    " Handle different keys
    if a:key >= '0' && a:key <= '9'
	let b:prev_popup_key = a:key
	let b:count = b:count .. a:key
	return 1

    elseif !empty(b:count)
	call win_execute(a:winid, 'normal! ' .. b:count .. a:key)
	let b:count = ""
	return 1

    elseif a:key == 'n' || a:key == 'j'
        " Move cursor down one line
        call win_execute(a:winid, 'normal! j')
        let b:prev_popup_key = (a:key == 'n' ? 'n' : 'j')
        return 1

    elseif a:key == 'p' || a:key == 'N' || a:key == 'k'
        " Move cursor up one line
        call win_execute(a:winid, 'normal! k')
        let b:prev_popup_key = (a:key == 'p' ? 'p' : (a:key == 'N' ? 'N' : 'k'))
        return 1

    elseif a:key == "\<Space>" || a:key == "\<C-F>"
        " Scroll one page downward
        call win_execute(a:winid, "normal! \<C-F>")
        let b:prev_popup_key = (a:key == "\<Space>" ? "\<Space>" : "\<C-F>")
        return 1

    elseif a:key == 'b' || a:key == "\<C-B>"
        " Scroll one page backward
        call win_execute(a:winid, "normal! \<C-B>")
        let b:prev_popup_key = (a:key == 'b' ? 'b' : "\<C-B>")
        return 1

    elseif a:key == 'G'
        " Jump to last item
        call win_execute(a:winid, 'normal! G')
        let b:prev_popup_key = 'G'
        return 1

    elseif a:key == 'g'
        " Check for gg sequence
        if b:prev_popup_key == 'g'
            " Jump to first item
            call win_execute(a:winid, 'normal! gg')
            let b:prev_popup_key = ''
        else
            let b:prev_popup_key = 'g'
        endif
        return 1

    elseif a:key == "\<Esc>"
        " Close popup on Escape
        let b:tex_labels_popup = -1
        let b:prev_popup_key = ''
        call popup_close(a:winid)
        return 1

    else
        " Close popup on any other key
        let b:tex_labels_popup = -1
        let b:prev_popup_key = ''
        call popup_close(a:winid)
        return 0
    endif
endfunction

" Insert selected reference
function! s:InsertReference(ref)
    let l:ref_name = a:ref

    " Find and replace reference in the triggering buffer
    let l:line = getline('.')
    let l:curr_offset = col('.') - 1

    " Find brace boundaries
    let l:start_col = s:SearchOpenBrace_left(l:line, l:curr_offset)
    let l:curlybrace_at = s:MatchCurlyBrace(l:line, l:start_col)
    let l:start_col += 1
    let l:end_col = l:curlybrace_at[1]

    " Replace reference and position cursor
    let l:new_line = strpart(l:line, 0, l:start_col) .. l:ref_name ..
		\ strpart(l:line, l:end_col)
    call setline('.', l:new_line)
    call feedkeys("\<Esc>", 'n')
    call cursor(line('.'), l:start_col + len(l:ref_name) + 2)
endfunction

" Popup filter function
function! s:PopupFilter(winid, key)
    " Store previous key for gg detection
    if !exists('b:prev_popup_key')
        let b:prev_popup_key = ''
    endif

    "let l:type = getwinvar(a:winid, 'type', '')

    " Store a digital number for repeated command
    if !exists('b:count')
	let b:count = ""
    endif

    " Handle different keys
    if a:key == "\<CR>"
        " Enter key - select and insert reference
        let l:buf = winbufnr(a:winid)
        let l:cursor_line = getbufoneline(l:buf, line('.', a:winid))
        if !empty(l:cursor_line)
            " Extract label from the line using the same format as in
	    " s:FormatMenuItem
            "let l:label = matchstr(l:cursor_line, '\v\{[^}]+\}')
            " Remove the braces
            "let l:label = substitute(l:label, '[{}]', '', 'g')
	    let l:curlybrace_at = s:MatchCurlyBrace(l:cursor_line)
	    if !empty(l:curlybrace_at)
		let l:label = strpart(l:cursor_line, l:curlybrace_at[0] + 1,
			    \ l:curlybrace_at[1] - l:curlybrace_at[0] - 1)
	    else
		let l:label = ''
	    endif
	else
	    let l:label = ''
        endif

	if !empty(l:label)
	    call s:InsertReference(l:label)
	endif
        let b:tex_labels_popup = -1
        call popup_close(a:winid)
        return !empty(l:label)

    else
        return s:Popup_KeyAction(a:winid, a:key)
    endif
endfunction

" Show the reference popup menu
"   s:Popup_Main(type, limit [, filename])
"   {type}	"label" or "bibitem"
"   {limit}	If {limit} is a positive integer and there are more than {limit}
"		items to select, the menu shows options whether to show them
"		according to source files or according to counters.
"		If {limit} is zero, all envolved items are shown in the menu.
"    {filename}
"		If {filename} is nonempty, only items from {filename} are
"		displayed for selection.
"
function! s:Popup_Main(type, limit, ...)
    " Close any existing popup first
    call s:CleanupPopup()

    if a:type != "label" && a:type != "bibitem" "&& a:type != "tag"
	call s:ShowWarningMessage('Type "' ..  a:type .. '" not supported.')
	return -1
    endif

    let b:tex_labels_item_overflow = 0
    if a:0 > 0 && !empty(a:1)
	let l:refs = s:GetRefItems(a:1, a:type)
	if a:limit > 0 && len(l:refs) > a:limit
	    call remove(l:refs, 0, -1)
	    let b:tex_labels_item_overflow = 1
	endif
    else
	let l:refs = s:GetAllReferences(a:type, a:limit)
    endif

    if b:tex_labels_item_overflow
	let b:tex_labels_item_overflow = 0
	" Here {l:refs} is empty. See, the codes of s:GetAllReferences() .

	if a:type == "label"
	    return s:Popup_FilesCounters()
	elseif a:type == "bibitem"
	    return s:Popup_Files("bibitem")
	endif
    elseif empty(l:refs)
	" Create error message or keep silence?
	call s:ShowWarningMessage("No labels found.")
	return -1
    endif

    if a:type == "label"
	let l:title = ' Label items '
    elseif a:type == "bibitem"
	let l:title = ' Bibliography items '
    endif
    let l:popup_config = {
		\ 'line': winline() + 1,
		\ 'col': wincol(),
		\ 'pos': 'topleft',
		\ 'maxheight': g:tex_labels_popup_height,
		\ 'maxwidth': winwidth(0) - 8,
		\ 'highlight': 'TexLabelsPopup',
		\ 'border': [1, 1, 1, 1],
		\ 'borderhighlight': ['TexLabelsPopupBorder'],
		\ 'title': l:title,
		\ 'titlehighlight': 'TexLabelsPopupTitle',
		\ 'cursorline': 1,
		\ 'zindex': 200,
		\ 'filter': function('s:PopupFilter')
		\ }

    " Create popup menu
    let l:refs_relative = []
    for formatted_line in l:refs
	call add(l:refs_relative, s:Refs_RelativePath(formatted_line, a:type))
    endfor

    let l:refs_relative = s:AlignMenuItem(l:refs_relative, a:type)

    let b:tex_labels_popup = popup_create(l:refs_relative, l:popup_config)
    if b:tex_labels_popup < 0
	return -1
    endif

    call setwinvar(b:tex_labels_popup, 'type', a:type)
    return 0
endfunction

" Popup filter function for counter menu
function! s:PopupFilter_counter(winid, key)
    let l:counter_then_file = getwinvar(a:winid, 'counter_then_file')

    if a:key == "\<CR>"
        let l:buf = winbufnr(a:winid)
        let l:counter = getbufoneline(l:buf, line('.', a:winid))
        if !empty(l:counter)
	    call popup_close(a:winid)
	    let b:tex_labels_popup = -1

	    if l:counter_then_file
		let l:status = s:Popup_Files("label", l:counter)
	    else
		let l:status = s:Popup_LabelsOfCounter(l:counter)
	    endif
	    return (l:status == 0)
	endif
    else
        return s:Popup_KeyAction(a:winid, a:key)
    endif
endfunction

" Open the counter-selection popup window
"   s:Popup_Counters(type [, file])
"   {type}	either "label" or "bibitem"
"   {file}	If not empty, search in this file only.
" When it is called in the form of
"   s:Popup_Counters(type, '')   or  s:Popup_Counters(type, "")
" a file-selection window pops up.  Hence the above form is different from
"   s:Popup_Counters(type)
function! s:Popup_Counters(type, ...)
    call s:CleanupPopup()

    if a:0 > 0 && !empty(a:1)
	let l:filename = a:1
    else
	let l:filename = ''
	let l:counter_then_file = (a:0 > 0)
    endif

    if a:type == "bibitem"
	if a:0 == 0
	    return s:Popup_Main("bibitem", 0)
	elseif !empty(a:1)
	    return s:Popup_Main("bibitem", 0, a:1)
	else
	    return s:Popup_Files("bibitem")
	endif

    elseif a:type != "label"
	call s:ShowWarningMessage("Unknown type \"" .. a:type .. "\".")
	return -1
    endif

    " From now on, a:type == 'label'

    let l:counters = s:GetAllCounters()
    if len(l:counters) == 1
	if l:counter_then_file
	    return s:Popup_Files("label")
	else
	    return s:Popup_Main("label", 0, l:filename)
	endif
    endif

    " In the following, there are at least two LaTeX counters.

    let l:popup_config = {
		\ 'line': winline() + 1,
		\ 'col': wincol(),
		\ 'pos': 'topleft',
		\ 'maxheight': g:tex_labels_popup_height,
		\ 'maxwidth': winwidth(0) - 8,
		\ 'highlight': 'TexLabelsPopup',
		\ 'border': [1, 1, 1, 1],
		\ 'borderhighlight': ['TexLabelsPopupBorder'],
		\ 'title': ' Search labels according to LaTeX counters ',
		\ 'titlehighlight': 'TexLabelsPopupTitle',
		\ 'cursorline': 1,
		\ 'zindex': 200,
		\ 'filter': function('s:PopupFilter_counter')
		\ }

    let b:tex_labels_popup = popup_create(l:counters, l:popup_config)

    if b:tex_labels_popup > 0
	call setwinvar(b:tex_labels_popup, 'counter_then_file',
		    \ l:counter_then_file)
	return 0
    else
	let b:tex_labels_popup = -1
	return -1
    endif
endfunction

" Popup filter function for file selection
function! s:PopupFilter_file(winid, key)
    let l:type = getwinvar(a:winid, 'type')
    let l:file_then_counter = getwinvar(a:winid, 'file_then_counter')

    " Store previous key for gg detection
    if !exists('b:prev_popup_key')
        let b:prev_popup_key = ''
    endif

    " Store a digital number for repeated command
    if !exists('b:count')
	let b:count = ""
    endif

    " Handle different keys
    if a:key == "\<CR>"
        " Enter key - select and insert reference
        let l:buf = winbufnr(a:winid)
        let l:file = getbufoneline(l:buf, line('.', a:winid))
        if !empty(l:file)
	    let b:tex_labels_popup = -1
	    call popup_close(a:winid)

	    if l:file_then_counter
		call s:Popup_Counters("label")
	    else
		call s:Popup_Main(l:type, 0, l:file)
	    endif
	    return 1
	else
	    call s:CleanupPopup()
	    return s:ShowWarningMessage("Blank line!")
        endif

	call s:CleanupPopup()
        "let b:tex_labels_popup = -1
        "call popup_close(a:winid)
	
        return 1

    else
        return s:Popup_KeyAction(a:winid, a:key)
    endif
endfunction

" Open the file-selection popup window.  Usage:
"   s:Popup_Files(type)
" or
"   s:Popup_Files("label", '')
" or
"   s:Popup_Files("label", counter)
" with
"   {type}	being "label" or "bibitem" only
"   {counter}	the name of a LaTeX counter
"
" Call s:Popup_Files(type) to list all files containing \label or \bibitem
" according to the value of {type}.  When one of these files is selected,
" a new " popup window shows all available labels or bibliographies generated
" in that file.
"
" Call s:Popup_Files("label", '') to list all files containing \label .
" When one of these files is selected, a new popup window shows all available
" LaTeX counters associated with \label .
"
" Call s:Popup_Files("label", counter) to list all files containing \label
" associated with the LaTeX counter {counter} associated with \label .
" When one of these files is selected, all available cross reference markers,
" belonging to this counter in the selected file, are listed in a new popup
" window.
function! s:Popup_Files(type, ...)
    " Close any existing popup first
    call s:CleanupPopup()

    if a:0 > 0 && empty(a:1) && a:type == "label"
	let l:file_then_counter = 1
    else
	let l:file_then_counter = 0
    endif

    if a:type != "label" && a:type != "bibitem"
	call s:ShowWarningMessage('s:Popup_Files: type "' .. a:type ..
		    \ '" not supported.')
	return -1
    endif

    let l:files = s:GetFilesContainingCommand(a:type)

    if empty(l:files)
	call s:ShowWarningMessage('No files containing "' .. a:type .. '".')
	return -1

    elseif len(l:files) == 1
	if l:file_then_counter
	    let l:status = s:Popup_Counters(a:type, l:files[0])
	    return (l:status == 0)
	else
	    let l:status = s:Popup_Main(a:type, 0, l:files[0])
	    return (l:status == 0)
	endif

    endif

    " Now len(l:files) > 1

    if a:0 > 0 && !empty(a:1) && a:type == "label"
	let l:effective_files = []
	for file in l:files
	    if s:HasCounterLabels(file, a:1)
		call add(l:effective_files, s:GetRelativePath(file))
	    endif
	endfor

	if !empty(l:effective_files)
	    let l:files = l:effective_files
	else
	    call s:ShowWarningMessage('No files containing a label belonging to the LaTeX counter "' .. a:1 .. '".')
	    return -1
	endif
    else
	let l:rel_files = []
	for file in l:files
	    call add(l:rel_files, s:GetRelativePath(file))
	endfor
	let l:files = l:rel_files
    endif

    let l:popup_config = {
		\ 'line': winline() + 1,
		\ 'col': wincol(),
		\ 'pos': 'topleft',
		\ 'maxheight': g:tex_labels_popup_height,
		\ 'maxwidth': winwidth(0) - 8,
		\ 'highlight': 'TexLabelsPopup',
		\ 'border': [1, 1, 1, 1],
		\ 'borderhighlight': ['TexLabelsPopupBorder'],
		\ 'title': ' Select a file to search ',
		\ 'titlehighlight': 'TexLabelsPopupTitle',
		\ 'cursorline': 1,
		\ 'zindex': 200,
		\ 'filter': function('s:PopupFilter_file')
		\ }

    " Create popup menu
    let b:tex_labels_popup = popup_create(l:files, l:popup_config)
    if b:tex_labels_popup > 0
	call setwinvar(b:tex_labels_popup, 'type', a:type)
	call setwinvar(b:tex_labels_popup, 'file_then_counter',
		    \ l:file_then_counter)
	"call setwinvar(b:tex_labels_popup, 'files', l:files)
	return 0
    else
	return -1
    endif
endfunction

" Popup filter function
function! s:PopupFilter_FileCounter(winid, key)
    let l:involved_files = getwinvar(a:winid, 'involved_files')
    let l:counters = getwinvar(a:winid, 'counters')

    " Handle different keys
    "if a:key =~# '^[1-3]'
	"call win_execute(a:winid, 'normal! ' .. a:key .. 'G')
        "return 1
    "
    if a:key == '1'
        let b:tex_labels_popup = -1
        let b:prev_popup_key = ''
        call popup_close(a:winid)

	call s:Popup_Main("label", 0)
	return 1

    elseif a:key == '2'
	if len(l:involved_files) > 1
	    let b:tex_labels_popup = -1
	    let b:prev_popup_key = ''
	    call popup_close(a:winid)

	    call s:Popup_Files("label")
	endif

	return 1

    elseif a:key == '3'
	if len(l:counters) > 1
	    let b:tex_labels_popup = -1
	    let b:prev_popup_key = ''
	    call popup_close(a:winid)

	    call s:Popup_Counters("label")
	endif

	return 1

    elseif a:key == '4'
	if len(l:involved_files) > 1 && len(l:counters) > 1
	    let b:tex_labels_popup = -1
	    let b:prev_popup_key = ''
	    call popup_close(a:winid)

	    call s:Popup_Files("label", '')

	endif

	return 1

    elseif a:key == '5'
	if len(l:involved_files) > 1 && len(l:counters) > 1
	    let b:tex_labels_popup = -1
	    let b:prev_popup_key = ''
	    call popup_close(a:winid)

	    call s:Popup_Counters("label", '')
	endif

	return 1

    elseif a:key == "\<CR>"
	let l:selection = line('.', a:winid)
	if l:selection == '1'
	    call s:Popup_Main("label", 0)
	elseif l:selection == '2'
	    if len(l:involved_files) > 1
		call s:Popup_Files("label")
	    endif
	elseif l:selection == '3'
	    if len(l:counters) > 1
		call s:Popup_Counters("label")
	    endif
	elseif l:selection == '4'
	    if len(l:involved_files) > 1 && len(l:counters) > 1
		call s:Popup_Files("label", '')
	    endif
	elseif l:selection == '5'
	    if len(l:involved_files) > 1 && len(l:counters) > 1
		call s:Popup_Counters("label", '')
	    endif
	endif

        let b:tex_labels_popup = -1
        let b:prev_popup_key = ''
        call popup_close(a:winid)

        return 1

    else
        let l:status = s:Popup_KeyAction(a:winid, a:key)
	let b:prev_popup_key = ''
	return l:status
    endif
endfunction

" Function to create a popup menu of how to list labels.  Usage:
"   s:Popup_FilesCounters()
" Only type "label" is processed.
function! s:Popup_FilesCounters()
    call s:CleanupPopup()

    let l:involved_files = s:GetFilesContainingCommand("label")
    if empty(l:involved_files)
	call s:ShowWarningMessage("No files found.")
	return -1
    endif

    let l:counters = s:GetAllCounters()
    if empty(l:counters)
	call s:ShowWarningMessage("No cross reference labels found.")
	return -1
    endif

    " Now both l:involved_files and l:counters are non-empty.

    let l:items = []
    call add(l:items, '[1] List all labels anyway')

    if len(l:involved_files) > 1 && len(l:counters) > 1
	call add(l:items, "[2] Select according to files")
	call add(l:items, "[3] Select according to counters")
	call add(l:items, "[4] Select through \"file -> counter\"")
	call add(l:items, "[5] Select through \"counter -> file\"")
    elseif len(l:involved_files) > 1
	call add(l:items, "[2] Select according to files")
	call add(l:items, "[3]")
	call add(l:items, "[4]")
	call add(l:items, "[5]")
    elseif len(l:counters) > 1
	call add(l:items, "[2]")
	call add(l:items, "[3] Select according to counters")
	call add(l:items, "[4]")
	call add(l:items, "[5]")
    endif

    if len(l:items) > 1
	let l:popup_config = {
		    \ 'line': winline() + 1,
		    \ 'col': wincol(),
		    \ 'pos': 'topleft',
		    \ 'maxheight': g:tex_labels_popup_height,
		    \ 'maxwidth': winwidth(0) - 8,
		    \ 'highlight': 'TexLabelsPopup',
		    \ 'border': [1, 1, 1, 1],
		    \ 'borderhighlight': ['TexLabelsPopupBorder'],
		    \ 'title': ' List by files or by counters ',
		    \ 'titlehighlight': 'TexLabelsPopupTitle',
		    \ 'cursorline': 1,
		    \ 'zindex': 200,
		    \ 'filter': function('s:PopupFilter_FileCounter')
		    \ }
	let b:tex_labels_popup = popup_create(l:items, l:popup_config)
	if b:tex_labels_popup > 0
	    call win_execute(b:tex_labels_popup, 'normal! j')
	    call setwinvar(b:tex_labels_popup, 'involved_files',
			\ l:involved_files)
	    call setwinvar(b:tex_labels_popup, 'counters', l:counters)
	    return 0
	else
	    return -1
	endif

    elseif len(l:involved_files) == 1
	return s:Popup_Counters("label", l:involved_files)
    else
	return 0
    endif
endfunction

" Popup filter function for selection and insertion of counter-labels
function! s:PopupFilter_CounterItems(winid, key)
    " Store previous key for gg detection
    if !exists('b:prev_popup_key')
        let b:prev_popup_key = ''
    endif

    " Store a digital number for repeated command
    if !exists('b:count')
	let b:count = ""
    endif

    " Handle different keys
    if a:key == "\<CR>"
        " Enter key - select and insert reference
        let l:buf = winbufnr(a:winid)
        let l:cursor_line = getbufoneline(l:buf, line('.', a:winid))
        if !empty(l:cursor_line)
            " Extract label from the line using the same format as in
	    " s:FormatMenuItem
	    let l:curlybrace_at = s:MatchCurlyBrace(l:cursor_line)
	    if !empty(l:curlybrace_at)
		let l:label = strpart(l:cursor_line, l:curlybrace_at[0] + 1,
			    \ l:curlybrace_at[1] - l:curlybrace_at[0] - 1)
	    else
		let l:label = ''
	    endif
	else
	    let l:label = ''
        endif

	if !empty(l:label)
	    call s:InsertReference(l:label)
	endif
        let b:tex_labels_popup = -1
        call popup_close(a:winid)
        return !empty(l:label)

    else
        return s:Popup_KeyAction(a:winid, a:key)
    endif
endfunction

" Open a popup window listing all labels under the LaTeX counter {counter_name}.
" Usage:
"   s:Popup_LabelsOfCounter(counter_name [, filename])
"   {counter_name}	the name of a LaTeX counter
"   {filename}		search in this file when presented and non-empty
function! s:Popup_LabelsOfCounter(counter_name, ...)
    "call s:CleanupPopup()

    if a:0 > 0 && !empty(a:1)
	let l:refs = s:GetRefItems(a:1, "label")
    else
	let l:refs = s:GetAllReferences("label", 0)
    endif

    if empty(a:counter_name)
	call s:ShowWarningMessage('No counter name')
	return -1
    elseif empty(l:refs)
	call s:ShowWarningMessage('No labels related to the counter ' ..
		    \ a:counter_name)
	return -1
    endif

    let l:labels = []
    for item in l:refs
	if item =~ a:counter_name
	    call add(l:labels, item)
	endif
    endfor

    let l:popup_config = {
		\ 'line': winline() + 1,
		\ 'col': wincol(),
		\ 'pos': 'topleft',
		\ 'maxheight': g:tex_labels_popup_height,
		\ 'maxwidth': winwidth(0) - 8,
		\ 'highlight': 'TexLabelsPopup',
		\ 'border': [1, 1, 1, 1],
		\ 'borderhighlight': ['TexLabelsPopupBorder'],
		\ 'title': ' Search cross reference labels... ',
		\ 'titlehighlight': 'TexLabelsPopupTitle',
		\ 'cursorline': 1,
		\ 'zindex': 200,
		\ 'filter': function('s:PopupFilter_CounterItems')
		\ }

    let b:tex_labels_popup = popup_create(l:labels, l:popup_config)
    if b:tex_labels_popup > 0
	"call setwinvar(b:tex_labels_popup, 'labels', l:labels)
	return 0
    else
	return -1
    endif
endfunction

function! s:PopupFilter_CheckLabels(winid, key)
    if a:key == "\<Esc>"
	call popup_close(a:winid)
	let b:tex_labels_popup = -1
	let b:tex_labels_counter = 0
	return 1
    else
	return 0
    endif
endfunction

" Function to check whether 'marker' in '\label{marker}', '\bibitem{marker}',
" '\tag{marker}' or '\include{marker}' is duplicated.
function! s:Popup_CheckLabels()
    let l:type = s:TriggerCheck()
    if l:type == "subf" || l:type == "supf"
	return s:Popup_CheckInclude()
    elseif l:type != "label" && l:type != "bibitem" && l:type != "tag"
	return -1
    endif

    let b:tex_labels_counter += 1
    if b:tex_labels_counter < g:tex_labels_check_length
	return 0
    else
        call s:CleanupPopup()
	let b:tex_labels_counter = 0
    endif

    let l:line = getline('.')
    let l:line_number = line('.')
    let l:curr_offset = col('.') - 1

    " Find the nearest '{' (not part of '\{') on the left of cursor
    let l:open_brace_at = s:SearchOpenBrace_left(l:line, l:curr_offset)
    if l:open_brace_at < 0
        return -1
    endif

    " Check if cursor is between '{' and '}'
    let l:curlybrace_at = s:MatchCurlyBrace(l:line, l:open_brace_at)
    if empty(l:curlybrace_at)
        return -1
    endif

    let l:close_brace_at = l:curlybrace_at[1]
    if l:close_brace_at < l:curr_offset
        return -1
    endif

    " Extract curr_marker: the string after the '{' and up to cursor position
    let l:curr_marker = strpart(l:line, l:open_brace_at + 1,
		\ l:curr_offset - l:open_brace_at - 1) .. v:char

    " If l:curr_marker is empty, don't show popup
    if empty(l:curr_marker)
        return -1
    endif

    " Get all label references
    let l:all_refs = s:GetAllReferences(l:type, 0)
    if empty(l:all_refs)
        return -1
    endif

    " Find labels that start with l:curr_marker
    let l:matching_refs = []
    for ref in l:all_refs
        " Extract label name from the formatted reference line
        let l:curlybrace_at_ref = s:MatchCurlyBrace(ref)
        if !empty(l:curlybrace_at_ref)
            let l:label_name = strpart(ref, l:curlybrace_at_ref[0] + 1,
			\ l:curlybrace_at_ref[1] - l:curlybrace_at_ref[0] - 1)
            if l:label_name =~ '^' .. l:curr_marker && (
			\ s:GetLineNumber(ref) != l:line_number ||
			\ s:GetAbsolutePath(s:GetFileName(ref)) !=
			\ expand("%:p")
			\ )
                call add(l:matching_refs, ref)
            endif
        endif
    endfor

    " If there are matching labels, show them in a popup
    if !empty(l:matching_refs)
        " Close any existing popup first
        call s:CleanupPopup()

        let l:popup_config = {
                    \ 'line': winline() + 1,
                    \ 'col': wincol() + 2,
                    \ 'pos': 'topleft',
                    \ 'maxheight': g:tex_labels_popup_height,
                    \ 'maxwidth': winwidth(0) - 8,
                    \ 'highlight': 'TexLabelsPopup',
                    \ 'border': [1, 1, 1, 1],
                    \ 'borderhighlight': ['TexLabelsPopupBorder'],
                    \ 'title': ' Matching Labels ',
                    \ 'titlehighlight': 'TexLabelsPopupTitle',
                    \ 'cursorline': 0,
                    \ 'zindex': 200,
                    \ 'filter': function('s:PopupFilter_CheckLabels')
                    \ }

        " Create popup menu
        let b:tex_labels_popup = popup_create(l:matching_refs, l:popup_config)
        if b:tex_labels_popup > 0
            return 0
        else
            return -1
        endif
    endif

    return -1
endfunction

" Check included files
" ????????????????????????????????????????????
function! s:Popup_CheckInclude()
    return 0
endfunction

" Check whether some action should be triggered
function! s:TriggerCheck()
    let l:line = getline('.')
    let l:offset = col('.') - 1

    " Quick check: if no '{' before cursor, return early
    let l:open_brace_at = s:SearchOpenBrace_left(l:line, l:offset)
    if l:open_brace_at < 0
	return ''
    endif

    " Check if cursor is between '{' and '}' .
    " Note that '{' with offset {l:open_brace_at} is not part of '\{'.
    let l:curlybrace_at = s:MatchCurlyBrace(l:line, l:open_brace_at)
    if empty(l:curlybrace_at)
	return ''
    endif

    let l:close_brace_at = l:curlybrace_at[1]
    if l:close_brace_at < l:offset
	return ''
    endif

    " Now the cursor is behide '{', and is before or at '}'.  That is,
    "	{l:open_brace_at} < {l:offset} <= {l:close_brace_at} .

    " Check if it's a command like \ref, \eqref, and so on
    let l:before_brace = strpart(l:line, 0, l:open_brace_at)
    if l:before_brace =~ '\v\\(ref|eqref|pageref)\s*$'
	call s:Update_AuxFiles()
	call s:Popup_Main("label", g:tex_labels_limit)
	return 'label'
    elseif l:before_brace =~ '\v\\cite\s*$'
	call s:Update_AuxFiles()
	call s:Popup_Main("bibitem", g:tex_labels_limit)
	return 'bibitem'
    elseif l:before_brace =~ '\v\\label\s*$'
	call s:Update_AuxFiles()
	return 'label'
    elseif l:before_brace =~ '\v\\tag\s*$'
	call s:Update_AuxFiles()
	return 'tag'
    elseif l:before_brace =~ '\v\\bibitem\s*(\[[^\]]*\])?\s*$'
	call s:Update_AuxFiles()
	return 'bibitem'
    elseif l:before_brace =~ '\v\\include\s*$'
	call s:Update_AuxFiles()
	return 'subf'
    elseif l:before_brace =~ '\v\\input\s*$'
	call s:Update_AuxFiles()
	return 'supf'
    endif

    return ''
endfunction

" Set up highlighting (only once globally)
if !exists('g:tex_labels_highlighted')
  let g:tex_labels_highlighted = 1

  if has('gui_running')
    execute 'highlight TexLabelsPopup guibg=' .. g:tex_labels_popup_bg ..
		\ ' guifg=black'
  else
      let cterm_color = g:tex_labels_popup_bg
    "let cterm_color = g:tex_labels_popup_bg == 'LightMagenta' ? '219' : (g:tex_labels_popup_bg == 'pink' ? '218' : 'magenta')
    execute 'highlight TexLabelsPopup ctermbg=' .. cterm_color .. ' ctermfg=0'
  endif

  highlight default TexLabelsPopupBorder guibg=gray guifg=black ctermbg=240 ctermfg=0
  highlight default TexLabelsPopupTitle guibg=darkgray guifg=white ctermbg=238 ctermfg=255
endif

" Setup function - called when this ftplugin is loaded
function! s:SetupTexLabels()
  " Trigger popup when entering insert mode
  autocmd InsertEnter <buffer> call s:TriggerCheck()

  " Trigger label check on each character entered in insert mode
  autocmd InsertCharPre <buffer> call s:Popup_CheckLabels()

  " Clean up popup when leaving buffer
  autocmd BufLeave <buffer> call s:CleanupPopup()

  " Add test command
  command! -buffer TestTexLabelsPopup call s:Popup_Main("label", g:tex_labels_limit)
  command! -buffer TestTexBibsPopup call s:Popup_Main("bibitem", g:tex_labels_limit)
endfunction


" Initialize the plugin
call s:Update_SubFiles()
call s:Update_AuxFiles()
call s:SetupTexLabels()
