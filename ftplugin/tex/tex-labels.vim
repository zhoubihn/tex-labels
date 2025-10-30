""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" ftplugin/tex/tex-labels.vim - LaTeX reference completion popup
" 	Provides popup menu for \ref, \eqref, \pageref, and \cite commands
"
" Maintainer:   Bin Zhou   <zhoub@bnu.edu.cn>
" Version:      0.3.33
"
" Upgraded on: Wed 2025-10-29 23:56:49 CST (+0800)
" Last change: Thu 2025-10-30 13:16:57 CST (+0800)
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
if !exists('g:tex_labels_popup_bg')
  let g:tex_labels_popup_bg = 'LightYellow'
endif

if !exists('g:tex_labels_popup_height')
  let g:tex_labels_popup_height = 8
endif

if !exists('g:tex_labels_limit')
    let g:tex_labels_limit = 4 * g:tex_labels_popup_height
elseif g:tex_labels_limit < max([g:tex_labels_popup_height, 8])
    let g:tex_labels_limit = max([g:tex_labels_popup_height, 8])
endif

" Searching for '%! Main file: ...' only in the top
" {g:tex_labels_mainfile_scope} lines of the current file.
if !exists('g:tex_labels_mainfile_scope')
    let g:tex_labels_mainfile_scope = 16
endif


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

    let clean_list = []
    for item in a:list
	if index(clean_list, item) == -1
	    call add(clean_list, item)
	endif
    endfor

    return clean_list
endfunction

" Function to obtain the absolute path of {filename}, with respect to {a:1}
" if it presents.
function! s:GetAbsolutePath(filename, ...)
    let path = expand(a:filename)

    if path =~ '^/'
	return simplify(path)
    endif

    if a:0 > 0 && !empty(a:1)
	let relative = expand(a:1)
    else
	let relative = expand("%")
    endif

    " relative path calculated:
    let path = fnamemodify(relative, ":p:h") .. "/" .. path
    return simplify(path)
endfunction


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
"	Fundamental functions related to TeX/LaTeX files
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Function returning a string with TeX comments removed from the string {text}.
function! s:RemoveTeXComment(text)
    let i = stridx(a:text, '%')
    if i == 0
	return ""
    elseif i < 0
	return a:text
    endif

    " Now there is '%' in {text} somewhere not in the beginning:
    while i > 0
	if  strpart(a:text, i - 1, 1) != '\'
	    return strpart(a:text, 0, i)
	else
	    let length = i
	    let i = stridx(a:text, '%', i + 1)
	endif
    endwhile

    return a:text
endfunction

" Function to match curly braces.  Note that '\{' and '\}' are ignored.
"	s:MatchCurlyBrace(text[, start])
"   {text}	string
"   {start}	offset where the search begins
function! s:MatchCurlyBrace(text, ...)
    let positions = []
    let text_len = len(a:text)

    if a:0 > 0
	let start = a:1
    else
	let start = 0
    endif

    if start >= text_len - 1
	" Starting position is so far away that no '}' can be found.
	return positions
    endif

    while 1
	let left_ind = match(a:text, '{', start)

	if left_ind < 0 || left_ind == text_len - 1
	    " No '{' found, or no '}' at all.
	    return positions
	elseif strpart(a:text, left_ind - 1, 1) == '\'
	    " '\{' is found, which is ignored.
	    let start = left_ind + 1
	    continue
	else
	    " Now '{' but not '\{' is found.
	    break
	endif
    endwhile

    " The first '{' has been found, not at the end.  That is,
    "		left_ind <= text_len -2 .
    let level = 0
    let right_ind = -1
    for i in range(left_ind + 1, text_len - 1)
	let char = strpart(a:text, i, 1)
	if char == '}' && strpart(a:text, i - 1, 1) != '\'
	    if level == 0
		let right_ind = i
		break
	    else
		let level -= 1
	    endif
	elseif char == '{' && strpart(a:text, i - 1, 1) != '\'
	    let level += 1
	endif
    endfor

    if right_ind < 0
	return positions
    else
	call extend(positions, [left_ind, right_ind])
	return positions
    endif
endfunction

" Function to locate '{', but not part of '\{', in the string {expr}
" with the greatest offset that is less than {curr_offset}
function! s:SearchOpenBrace_left(expr, curr_offset)
    if empty(a:expr) || a:curr_offset <= 0
	return -1
    endif

    let length = min([len(a:expr), a:curr_offset])
    " Then {length} >= 1

    while length > 0
	let offset = strridx( strpart(a:expr, 0, length), '{' )
	if offset <= 0
	    " '{' not found, or at the beginning of {expr}
	    return offset
	endif

	" Then {offset} >= 1

	if strpart(a:expr, offset - 1, 1) != '\'
	    return offset
	elseif offset == 1
	    " Only a single '\{' is found.
	    return -1
	else
	    " {offset} >= 2
	    let length = offset - 1
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

    let lines = readfile(a:filename, '', g:tex_labels_mainfile_scope)
    let line_num = len(lines)

    for i in range(line_num)
        let line = lines[i]
        let matches = matchlist(line, '%! Main file:[ \t]*\([^ \t\n\r]*\)')
        if len(matches) > 1
            let main_file = matches[1]
	    if empty(main_file)
		continue
	    else
		return s:GetAbsolutePath(main_file, a:filename)
	    endif
        endif
    endfor

    " Maybe {filename} should be returned instead?
    return ''
endfunction

" File name of the main LaTeX file
" Maybe always updated?
if !exists('b:tex_labels_MainFile')
    let b:tex_labels_MainFile = s:FindMainFile(@%)
endif

" Function to obtain the name of auxiliary file
"   {type}	"incl", "label", "bibitem" or "tag"
function! s:AuxFileName(filename, type)
    if empty(a:filename)
	return ''
    elseif a:type != "incl" && a:type != "label" && a:type != "bibitem" &&
		\ a:type != "tag"
	return ''
    endif

    if a:filename =~ '\.tex$'
	return substitute(a:filename, 'tex$', a:type, '')
    else
	return a:filename .. '.' .. a:type
    endif
endfunction

" Function to find included files recursively
" The second parameter triggers a recursive search.
function! s:FindIncludedFiles(main_file, ...)
    let included_files = []
    let main_file = s:GetAbsolutePath(a:main_file)
    let current_file = s:GetAbsolutePath("%")

    if !filereadable(main_file)
        return included_files
    endif

    if main_file ==# current_file && &modified
	" {main_file} is the current file and is modified:
	let lines_read = getbufline('%', 1, '$')
    elseif has("win64") || has("win32")
	let lines_read = readfile(main_file)
    else
	let lines_read = systemlist('grep \include{ ' .. shellescape(main_file))
	let lines_read = extend(lines_read,
		    \ systemlist('grep \input{ ' .. shellescape(main_file))
		    \ )
    endif

    for line in lines_read
        " Remove comments
        let clean_line = s:RemoveTeXComment(line)

        " Check for \include and \input
        for cmd in ['include', 'input']
	    let start = match(clean_line, '\\' .. cmd)
	    if start < 0
		continue
	    endif

	    let curlybrace_at = s:MatchCurlyBrace(clean_line, start)
	    if !empty(curlybrace_at)
		let included_file = strpart(clean_line, curlybrace_at[0] + 1,
			    \ curlybrace_at[1] - curlybrace_at[0] - 1
			    \ )
                let included_file = trim(included_file)
		if empty(included_file)
		    continue
		endif

		if included_file !~ '\.tex$'
		    let included_file = included_file .. '.tex'
		endif
                let included_file = s:GetAbsolutePath(included_file, main_file)
                call add(included_files, included_file)

                " Recursively find files in the included file
		if a:0 > 0
		    let sub_files = s:FindIncludedFiles(included_file, 1)
		    call extend(included_files, sub_files)
		endif
            endif
        endfor
    endfor

    return s:RemoveDuplicates(included_files)
endfunction

" Behaving like GNU make, the function s:Update_InclFile([filename]) updates
" the auxiliary file
"   substitute(filename, '\.tex$', '\.incl', '').
" If {filename} is omitted or empty, its default value is
"	b:tex_labels_MainFile when it is nonempty; or
"	the current file provided that b:tex_labels_MainFile is empty.
function! s:Update_InclFile(...)
    " Set the value of {filename}
    if a:0 > 0 && !empty(a:1)
	let filename = s:GetAbsolutePath(a:1)
    elseif !empty(b:tex_labels_MainFile)
	let filename = b:tex_labels_MainFile
    else
	let filename = s:GetAbsolutePath("%")
    endif

    if filename !~ '\.tex$'
	echo "s:Update_InclFile: File name <" .. filename ..
		    \ "> without postfix <.tex>?"
	echo "s:Update_InclFile stops."
	return -1
    endif

    " The file <xxx.incl> is in the same directory of <xxx.tex>.
    let target = s:AuxFileName(filename, 'incl')
    let included_files = []

"    if getftype(filename) == "link"
"	let filename = resolve(filename)
"    endif

    if !filereadable(filename)
	echo "s:Update_InclFile: file <" .. filename .. "> not readable."
	echo "s:Update_InclFile stops."
	return -1
    endif

    if empty(getfperm(target)) || getftime(filename) > getftime(target)
	let included_files = s:FindIncludedFiles(filename)
	call writefile(included_files, target)
    endif

    let included_files = readfile(target)

    if empty(included_files)
	return 0
    endif

    for file in included_files
	if !empty(file) && s:Update_InclFile(file) < 0
	    return -1
	endif
    endfor
    return 0
endfunction

" Function to get all relevant files to search
" call s:GetFilesToSearch([main_file])
function! s:GetFilesToSearch(...)
    let current_file = s:GetAbsolutePath("%")
    let files = []
    let roots = []

    if a:0 > 0 && !empty(a:1)
	let main_file = s:GetAbsolutePath(a:1)
    elseif !empty(b:tex_labels_MainFile)
	let main_file = b:tex_labels_MainFile
    else
	let main_file = current_file
    endif
    " Now {main_file} is nonempty

    " The current file is always included, being the first to search.
    call add(roots, current_file)

    if main_file != current_file && filereadable(main_file)
	call add(roots, main_file)
    endif

    " Files included by searched files are also searched.
    for root_file in roots
	call add(files, root_file)

	if s:Update_InclFile(root_file) < 0
	    continue
	endif

	let root_incl = s:AuxFileName(root_file, 'incl')
	if !filereadable(root_incl)
	    continue
	endif

	let included_files = readfile(root_incl)
	call extend(files, included_files)

	for file in included_files
	    call extend(files, s:GetFilesToSearch(file))
	endfor
    endfor

    " Remove duplicates
    return s:RemoveDuplicates(files)
endfunction

" Function to extract labels and bibitems from a file, with
"   {type}		'label', 'bibitem' or 'tag'
" For the first time to call it, do the following:
function! s:ExtractLabelsBibitemsTags(filename, type)
    let items = []
    let filename = s:GetAbsolutePath(a:filename)
    let current_file = s:GetAbsolutePath("%")

    if empty(a:filename) || !filereadable(filename)
	return items
    endif

    let grep_called = 0
    if filename ==# current_file && &modified
	" {main_file} is the current file and is modified:
	let lines = getbufline('%', 1, '$')
    elseif has("win64") || has("win32")
	let lines = readfile(filename)
    else
	let lines = systemlist('grep -n \' .. a:type .. '.*{ ' ..
		    \ shellescape(filename))
	let grep_called = 1
    endif

    if empty(lines)
	return items
    endif

    for i in range(len(lines))
        let line = lines[i]
        let line_num = i + 1

        " Remove comments
        let clean_line = s:RemoveTeXComment(line)
        if empty(clean_line)
            continue
        endif

        " Search commands \label, \bibitem or \tag
        let start = match(clean_line, '\\' .. a:type)
	if start < 0
	    continue
	endif

	let curlybrace_at = s:MatchCurlyBrace(clean_line, start)
	if !empty(curlybrace_at)
	    let label = strpart(clean_line, curlybrace_at[0] + 1,
			\ curlybrace_at[1] - curlybrace_at[0] - 1
			\ )

	    if grep_called
		let line_num = matchstr(clean_line, '^\([^:]*\):')
	    else
		let line_num = i + 1
	    endif

            let item = {
			\ 'idcode': label,
			\ 'counter': a:type == 'label' ? '??' : a:type,
			\ 'idnum': '??',
			\ 'page': '??',
			\ 'line': line_num,
			\ 'file': fnamemodify(a:filename, ':t'),
			\ 'full_path': a:filename
			\ }
	    call add(items, item)
	endif
    endfor

    return items
endfunction

" Function to parse auxiliary file for numbering information
function! s:ParseAuxFile(aux_file)
    let label_data = {}
    let bib_data = {}

    if !filereadable(a:aux_file)
        return []
    endif

    let aux_lines = readfile(a:aux_file)

    for line in aux_lines
        " Parse \newlabel commands
	let start = match(line, '\\newlabel')
	if start >= 0
	    let curlybrace_at = s:MatchCurlyBrace(line, start)
	    if !empty(curlybrace_at)
		let label = strpart(line, curlybrace_at[0] + 1,
			    \ curlybrace_at[1] - curlybrace_at[0] - 1
			    \ )

		let start = curlybrace_at[1] + 2
		let curlybrace_at = s:MatchCurlyBrace(line, start)
		let num = strpart(line, curlybrace_at[0] + 1,
			    \ curlybrace_at[1] - curlybrace_at[0] - 1
			    \ )

		let start = curlybrace_at[1] + 1
		let matches = matchlist(line, '{\([^}]*\)}{\([^}]*\)}{\([^\.]*\)\.', start)

		if len(matches) > 3
		    let page = matches[1]
		    let counter = matches[3]
		    let label_data[label] = {'counter': counter, 'idnum': num, 'page': page}
		endif
	    endif
	endif

        " Parse \bibcite commands
	let start = match(line, '\\bibcite')
	if start >= 0
	    let curlybrace_at = s:MatchCurlyBrace(line, start)
	    if !empty(curlybrace_at)
		let bibitem = strpart(line, curlybrace_at[0] + 1,
			    \ curlybrace_at[1] - curlybrace_at[0] - 1
			    \ )
		let start = curlybrace_at[1] + 1

		let matches = matchlist(line, '{\([^}]*\)}', start)
		if len(matches) > 1
		    let num = matches[1]
		    let bib_data[bibitem] = {'counter': 'bibitem', 'idnum': num, 'page': ''}
		endif
	    endif
        endif
    endfor

    return [label_data, bib_data]
endfunction


" Function to process selected file
function! s:CompleteLabelInfo(file, type)
    if a:type != "label" && a:type != "bibitem" && a:type != "tag"
	echo "s:CompleteLabelInfo: Unknown type " .. a:type .. "."
	return []
    endif

    let file = s:GetAbsolutePath(a:file)
    let b:tex_labels_item_overflow = 0
    let items = s:ExtractLabelsBibitemsTags(file, a:type)

    if empty(items)
	return items
    elseif b:tex_labels_item_overflow
	call remove(items, 0, -1)
	return []
    endif

    if a:type == "tag"
	return items
    endif

    " Parse auxiliary file for numbering
    let aux_file = fnamemodify(a:file, ':r') .. '.aux'
    let data_ParseAuxFile = s:ParseAuxFile(aux_file)
    if a:type == 'label'
	let aux_data = data_ParseAuxFile[0]
    else
	let aux_data = data_ParseAuxFile[1]
    endif

    " Merge auxiliary data
    for item in items
        if has_key(aux_data, item.idcode)
            let item.idnum = aux_data[item.idcode].idnum
	    if a:type == "label"
		let item.counter = aux_data[item.idcode].counter
		let item.page = aux_data[item.idcode].page
	    endif
        endif
    endfor

    return items
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
	return "(" .. a:item.counter .. ": " .. a:item.idnum .. ")\t{" ..
		    \ a:item.idcode .. "} {page: " .. a:item.page ..
		    \ "} {line: " .. a:item.line .. "} {file: " ..
		    \ a:item.file .. "}"

    elseif a:type == "bibitem"
	if a:item.counter != "bibitem"
	    echo "s:FormatMenuItem: corrupted data.  Nothing returned."
	    "return ''
	endif

	return "Ref. [" .. a:item.idnum .. "]\t{" ..
		    \ a:item.idcode .. "} {line: " .. a:item.line ..
		    \ "} {file: " .. a:item.file .. "}"

    elseif a:type == "tag"
	if a:item.counter != "tag"
	    echo "s:FormatMenuItem: corrupted data.  Nothing returned."
	    return ''
	endif

	return "(tag: " .. a:item.idcode .. ")\t{line: " ..
		    \ a:item.line .. "} {file: " .. a:item.file .. "}"

    else
	echo "s:FormatMenuItem: Unknown type " .. a:type ..
		    \ ".  Nothing returned."
	return ''
    endif
endfunction

" Behaving like GNU make, the function
"	s:Update_AuxFiles([type [, filename]])
" updates auxiliary files <file.type> when {type} is given as "label", "bibitem"
" or "tag", and {file} is
"	substitute(filename, '\.tex$', '.' .. type, '')
" when {filename} is also given.
" When {filename} is omitted, each file (except for the current file)
" listed in the file
" 	substitute(b:tex_labels_MainFile, '\.tex$', '\.incl', '')
" is checked and updated, if necessary.
" When {type} is not given, either, files with postfix ".label" and ".bibitem"
" are all updated, if necessary.
"
"   {type}	"label", "bibitem" or "tag"
function! s:Update_AuxFiles(...)
    let current_file = s:GetAbsolutePath('%')
    let target_items = []
    let type = ''
    let status = 0

    if a:0 >= 2
	if a:1 != 'label' &&  a:1 != 'bibitem' && a:1 != 'tag'
	    echo "s:Update_AuxFiles: Unknown  type \'" .. a:1 ..
			\ "\'.  Nothing done."
	    return -1
	else
	    let type = a:1
	endif

	if !empty(a:2)
	    let filename = s:GetAbsolutePath(a:2)
	    let aux_file = s:AuxFileName(filename, type)
	else
	    return s:Update_AuxFiles(type)
	endif

"	if getftype(a:2) == "link"
"	    let filename = resolve(a:2)
"	else
"	    let filename = a:2
"	endif

	if filereadable(filename) && ( empty(getfperm(aux_file)) ||
		    \ getftime(filename) > getftime(aux_file)
		    \ )
	    if s:Update_InclFile(filename) < 0
		return -1
	    endif

	    let info_items = s:CompleteLabelInfo(filename, type)
	    if len(info_items) > 0
		for item in info_items
		    call add(target_items, s:FormatMenuItem(item, type))
		endfor
	    endif

	    return writefile(target_items, aux_file)
	endif

	return 0

    elseif a:0 == 1
	call s:Update_InclFile()

	if !empty(b:tex_labels_MainFile)
	    let main_file = b:tex_labels_MainFile
	else
	    let main_file = current_file
	endif

	let incl_file = s:AuxFileName(main_file, 'incl')
	if filereadable(incl_file)
	    let searched_files = readfile(incl_file)
	else
	    echo "s:Update_AuxFiles: File <" .. incl_file ..
			\ "> does not exist or is not readble."
	    return -1
	endif

	for file in searched_files
	    " Auxiliary files related to the current file are not updated:
	    "if fnamemodify(file, ':p') == current_file
	"	continue
	    "endif

	    if s:Update_AuxFiles(a:1, file) < 0
		let status = -1
	    endif
	endfor

	return status

    else
	for type in ["label", "bibitem", "tag"]
	    if s:Update_AuxFiles(type) < 0
		let status = -1
	    endif
	endfor

	return status
    endif
endfunction



if !empty(b:tex_labels_MainFile)
    call s:Update_AuxFiles()
endif

" Necessary when {b:tex_labels_MainFile} is empty
call s:Update_InclFile(@%)
for type in ["label", "bibitem", "tag"]
    call s:Update_AuxFiles(type, @%)
endfor


" Function to get all relevant files containing \label, \bibitem or \tag
"   s:GetFilesContainingCommand({type}[, {mainfile}])
"   {type}	either "label", "bibitem" or "tag"
function! s:GetFilesContainingCommand(type, ...)
    if a:type != "label" && a:type != "bibitem" && a:type != "tag"
	echo 's:GetFilesContainingCommand: unknown type "' .. a:type .. '"'
	return -1
    endif

    if a:0 > 0
	let mainfile = a:1
	if s:Update_AuxFiles(a:type, mainfile) < 0
	    echo 's:GetFilesContainingCommand: error form s:Update_AuxFiles'
	    return -1
	endif

    else
	let mainfile = ''
	if s:Update_AuxFiles(a:type) < 0
	    echo 's:GetFilesContainingCommand: error form s:Update_AuxFiles'
	    return -1
	endif
    endif


    let effective_files = []
    let b:tex_labels_item_overflow = 0
    if empty(mainfile)
	let files = s:GetFilesToSearch()
    else
	let files = s:GetFilesToSearch(mainfile)
    endif

    for file in files
	let aux_file = s:AuxFileName(file, a:type)

	if getfsize(aux_file) > 0 || getfsize(aux_file) == -2
	    call add(effective_files, file)
	endif
    endfor

    return effective_files
endfunction

" Function to generate a List for \ref , \eqref , \pageref , \cite ,
" \label , \bibitem or \tag
"   {type}	"label", "bibitem" or "tag"
function! s:GetRefItems(filename, type)
    if a:type != "label" && a:type != "bibitem" && a:type != "tag"
	echo "s:GetRefItems: unknown type \"" .. a:type .. "\""
	return []
    endif

    let filename = s:GetAbsolutePath(a:filename)
    let current_file = s:GetAbsolutePath('%')

    let aux_file = s:AuxFileName(filename, a:type)

    let refs = []
    if filename == current_file && &modified
	let items = s:CompleteLabelInfo(a:filename, a:type)

	if empty(items)
	    return refs
	endif

	for i in items
	    let ref_item = s:FormatMenuItem(i, a:type)
	    call add(refs, ref_item)
	endfor

	return refs

    elseif !filereadable(aux_file)
	return refs
    else
	call s:Update_AuxFiles(a:type, filename)
	let refs = readfile(aux_file)
	return refs
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
	echo 's:GetAllReferences: unknown type "' .. a:type .. '".'
	return []
    endif

    let refs = []
    let files = s:GetFilesToSearch()

    for file in files
	call extend(refs, s:GetRefItems(file, a:type))
	if a:limit > 0 && len(refs) > a:limit
	    call remove(refs, 0, -1)
	    let b:tex_labels_item_overflow = 1
	    return refs
	endif
    endfor

    return refs
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
    let text = []
    call add(text, a:message)
    call add(text, "")
    call add(text, "Press any key to close this window.")

    let popup_config = {
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
    call popup_create(text, popup_config)
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

" Open the file-selection popup window
" {type}	being "label" or "bibitem" only
function! s:Popup_Files(type)
    " Close any existing popup first
    call s:CleanupPopup()

    if a:type != "label" && a:type != "bibitem"
	echo 's:Popup_Files: invalid type "' .. a:type .. '".'
	return -1
    endif

    let files = s:GetFilesContainingCommand(a:type)
    if empty(files)
	call s:ShowWarningMessage('No files containing "\' .. a:type .. '"')
	return -1
    elseif len(files) == 1
	call s:CleanupPopup()
	return s:Popup_Main(a:type, 0, files[0])
    endif

    if a:type == "label"
	let title = ' Select a file to search: '
    elseif a:type == "bibitem"
	let title = ' Select the counter the wanted label is related to: '
    else
	call s:ShowWarningMessage('s:Popup_Files: invalid type "' ..&nbsp;
		    \ a:type .. '"')
	return -1
    endif

    let popup_config = {
		\ 'line': winline() + 1,
		\ 'col': wincol(),
		\ 'pos': 'topleft',
		\ 'maxheight': g:tex_labels_popup_height,
		\ 'maxwidth': winwidth(0) - 8,
		\ 'highlight': 'TexLabelsPopup',
		\ 'border': [1, 1, 1, 1],
		\ 'borderhighlight': ['TexLabelsPopupBorder'],
		\ 'title': title,
		\ 'titlehighlight': 'TexLabelsPopupTitle',
		\ 'cursorline': 1,
		\ 'zindex': 200,
		\ 'filter': function('s:PopupFilter_file')
		\ }

    " Create popup menu
    let b:tex_labels_popup = popup_create(files, popup_config)
    if b:tex_labels_popup > 0
	call setwinvar(b:tex_labels_popup, 'type', a:type)
	"call setwinvar(b:tex_labels_popup, 'files', files)
	return 0
    else
	return -1
    endif
endfunction

" Open the counter-selection popup window
"   s:Popup_Counters(type[, file])
"   {type}	either "label" or "bibitem"
"   {file}	If not empty, search in this file only.
function! s:Popup_Counters(type, ...)
endfunction

" Popup filter function
function! s:PopupFilter_FileCounter(winid, key)
    let type = getwinvar(a:winid, 'type')

    " Handle different keys
    "if a:key =~# '^[1-3]'
	"call win_execute(a:winid, 'normal! ' .. a:key .. 'G')
        "return 1
    "
    if a:key == '1'
	call s:Popup_Files(type)
	return 1

    elseif a:key == '2'
	call s:Popup_Counters(type)
	return 1

    elseif a:key == '3'
	call s:Popup_Main(type, 0)
	return 1

    elseif a:key == "\<CR>"
	let selection = line('.', a:winid)
	if selection == 1
	    call s:Popup_Files(type)
	elseif selection == 2
	    call s:Popup_Counters(type)
	elseif selection == 3
	    call s:Popup_Main(type, 0)
	endif

        let b:tex_labels_popup = -1
        let b:prev_popup_key = ''
        call popup_close(a:winid)

        return 1

    else
        let status = s:Popup_KeyAction(a:winid, a:key)
	let b:prev_popup_key = ''
	return status
    endif
endfunction

" Function to create a popup menu of how to list labels or bibitems
"   s:FilesOrCounters()
" What value should be returned?
"
function! s:FilesOrCounters()
    call s:CleanupPopup()

    let items = []
    call add(items, "[1] Select according to files")
    call add(items, "[2] Select according to counters")
    call add(items, '[3] List all labels anyway')

    let involved_files = s:GetFilesContainingCommand("label")
    if len(involved_files) > 1
	let popup_config = {
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
	let b:tex_labels_popup = popup_create(items, popup_config)
	if b:tex_labels_popup > 0
	    "call win_execute(b:tex_labels_popup, 'normal! 2j')
	    "call setwinvar(b:tex_labels_popup, 'type', a:type)
	    return 0
	else
	    return -1
	endif

    elseif len(involved_files) == 1
	return s:Popup_Counters("label", involved_files)
    else
	return 0
    endif
endfunction

" Show the reference popup menu
"   s:Popup_Main(type, limit[, filename])
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
	let refs = s:GetRefItems(a:1, a:type)
	if a:limit > 0 && len(refs) > a:limit
	    call remove(refs, 0, -1)
	    let b:tex_labels_item_overflow = 1
	endif
    else
	let refs = s:GetAllReferences(a:type, a:limit)
    endif

    if b:tex_labels_item_overflow
	let b:tex_labels_item_overflow = 0
	" Here {refs} is empty. See, the codes of s:GetAllReferences() .

	if a:type == "label"
	    return s:FilesOrCounters()
	elseif a:type == "bibitem"
	    return s:Popup_Files("bibitem")
	endif
    elseif empty(refs)
	" Create error message or keep silence?
	call s:ShowWarningMessage("No labels found.")
	return
    endif

    if a:type == "label"
	let title = ' Label items '
    elseif a:type == "bibitem"
	let title = ' Bibliography items '
    endif
    let popup_config = {
		\ 'line': winline() + 1,
		\ 'col': wincol(),
		\ 'pos': 'topleft',
		\ 'maxheight': g:tex_labels_popup_height,
		\ 'maxwidth': winwidth(0) - 8,
		\ 'highlight': 'TexLabelsPopup',
		\ 'border': [1, 1, 1, 1],
		\ 'borderhighlight': ['TexLabelsPopupBorder'],
		\ 'title': title,
		\ 'titlehighlight': 'TexLabelsPopupTitle',
		\ 'cursorline': 1,
		\ 'zindex': 200,
		\ 'filter': function('s:PopupFilter')
		\ }

    " Create popup menu
    let b:tex_labels_popup = popup_create(refs, popup_config)
    if b:tex_labels_popup < 0
	return -1
    endif

    call setwinvar(b:tex_labels_popup, 'type', a:type)
    return 0
endfunction

" Check whether some action should be triggered
function! s:TriggerCheck()
    let line = getline('.')
    let offset = col('.') - 1

    " Quick check: if no '{' before cursor, return early
    let open_brace_at = s:SearchOpenBrace_left(line, offset)
    if open_brace_at < 0
	return -1
    endif

    " Check if cursor is between '{' and '}' .
    " Note that '{' with offset {open_brace_at} is not part of '\{'.
    let curlybrace_at = s:MatchCurlyBrace(line, open_brace_at)
    if empty(curlybrace_at)
	return -1
    endif

    " {open_brace_at} == curlybrace_at[0]
    "let open_brace_at = curlybrace_at[0]
    let close_brace_at = curlybrace_at[1]
    if close_brace_at < offset
	return -1
    endif

    " Now the cursor is behide '{', and is before or at '}'.  That is,
    "	{open_brace_at} < {offset} <= {close_brace_at} .

    " Check if it's a command like \ref, \eqref, and so on
    let before_brace = strpart(line, 0, open_brace_at)
    if before_brace =~ '\v\\(ref|eqref|pageref)\s*$'
	return s:Popup_Main("label", g:tex_labels_limit)
    elseif before_brace =~ '\v\\cite\s*$'
	return s:Popup_Main("bibitem", g:tex_labels_limit)
    elseif before_brace =~ '\v\\(label|tag)\s*$'
	return s:CheckLabels()
    elseif before_brace =~ '\v\\bibitem(\[[^\]]*\])?\s*\[([^][{}]*)\]\s*$'
	return s:CheckBibitems()
    elseif before_brace =~ '\v\\includeonely\s*$'
	return s:CheckIncludedFiles()
    endif

    return 0
endfunction

" Check labels
function! s:CheckLabels()
endfunction

" Check bibitem labels
function! s:CheckBibitems()
endfunction

" Check included files
function! s:CheckIncludedFiles()
endfunction

" Popup filter function
function! s:PopupFilter(winid, key)
    " Store previous key for gg detection
    if !exists('b:prev_popup_key')
        let b:prev_popup_key = ''
    endif

    "let type = getwinvar(a:winid, 'type', '')

    " Store a digital number for repeated command
    if !exists('b:count')
	let b:count = ""
    endif

    " Handle different keys
    if a:key == "\<CR>"
        " Enter key - select and insert reference
        let buf = winbufnr(a:winid)
        let cursor_line = getbufoneline(buf, line('.', a:winid))
        if !empty(cursor_line)
            " Extract label from the line using the same format as in
	    " s:FormatMenuItem
            "let label = matchstr(cursor_line, '\v\{[^}]+\}')
            " Remove the braces
            "let label = substitute(label, '[{}]', '', 'g')
	    let curlybrace_at = s:MatchCurlyBrace(cursor_line)
	    if !empty(curlybrace_at)
		let label = strpart(cursor_line, curlybrace_at[0] + 1,
			    \ curlybrace_at[1] - curlybrace_at[0] - 1)
	    else
		let label = ''
	    endif
	else
	    let label = ''
        endif

	if !empty(label)
	    call s:InsertReference(label)
	endif
        let b:tex_labels_popup = -1
        call popup_close(a:winid)
        return !empty(label)

    else
        return s:Popup_KeyAction(a:winid, a:key)
    endif
endfunction

" Insert selected reference
function! s:InsertReference(ref)
    let ref_name = a:ref

    " Find and replace reference in the triggering buffer
    let line = getline('.')
    let col = col('.') - 1

    " Find brace boundaries
    let start_col = strridx(strpart(line, 0, col), '{') + 1
    let end_col = stridx(line, '}', col)

    " Replace reference and position cursor
    let new_line = strpart(line, 0, start_col) .. ref_name ..
		\ strpart(line, end_col)
    call setline('.', new_line)
    call feedkeys("\<Esc>", 'n')
    call cursor(line('.'), start_col + len(ref_name) + 2)
endfunction

" Popup filter function for file selection
" ???????????????????????????????????????????????????!!!!!!!!!!!!!!
function! s:PopupFilter_file(winid, key)
    let type = getwinvar(a:winid, 'type')

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
        let buf = winbufnr(a:winid)
        let file = getbufoneline(buf, line('.', a:winid))
        if !empty(file)
	    let b:tex_labels_popup = -1
	    call popup_close(a:winid)

	    call s:Popup_Main(type, 0, file)
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

" Popup filter function
" ??????????????????????????????????????????????!!!!!!!!!!!!!!!!!!!!!
" Obsolete?
function! s:PopupFilter_bibitem(winid, key)
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

    elseif a:key == "\<CR>"
        " Enter key - select and insert reference
        let buf = winbufnr(a:winid)
        let cursor_line = getbufoneline(buf, line('.', a:winid))
        if !empty(cursor_line)
            " Extract label from the line using the same format as in
	    " s:FormatMenuItem
            let label = matchstr(cursor_line, '\v\{[^}]+\}')
            " Remove the braces
            let label = substitute(label, '[{}]', '', 'g')
	else
	    let label = ''
        endif

	call s:InsertReference(label)
        let b:tex_labels_popup = -1
        call popup_close(a:winid)
        return 1

    elseif a:key == "\<Esc>"
        " Close popup on Escape
        let b:tex_labels_popup = -1
        call popup_close(a:winid)
        return 1

    else
        " Close popup on any other key
        let b:tex_labels_popup = -1
        call popup_close(a:winid)
        return 0
    endif
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

  " Clean up popup when leaving buffer
  autocmd BufLeave <buffer> call s:CleanupPopup()

  " Add test command
  command! -buffer TestTexLabelsPopup call s:Popup_Main(g:tex_labels_limit)
endfunction

" Initialize the plugin
call s:SetupTexLabels()
