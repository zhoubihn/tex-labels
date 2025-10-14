""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" ftplugin/tex/tex-labels.vim - LaTeX reference completion popup
" 	Provides popup menu for \ref, \eqref, \pageref, and \cite commands
"
" Maintainer:   Bin Zhou
" Version:      0.2
"
" Upgraded on: Wed 2025-10-15 01:47:33 CST (+0800)
" Last change: Wed 2025-10-15 03:28:26 CST (+0800)
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Only load once per buffer
if exists('b:loaded_tex_labels')
  finish
endif
let b:loaded_tex_labels = 1

" Configuration options
if !exists('g:tex_labels_popup_bg')
  let g:tex_labels_popup_bg = 'LightMagenta'
endif

if !exists('g:tex_labels_popup_height')
  let g:tex_labels_popup_height = 6
endif

" Current popup ID (buffer-local)
let b:tex_labels_popup = -1

" Setup function - called when this ftplugin is loaded
function! s:SetupTexLabels()
  " Trigger popup when entering insert mode
  autocmd InsertEnter <buffer> call s:TriggerCheck()

  " Clean up popup when leaving buffer
  autocmd BufLeave <buffer> call s:CleanupPopup()

  " Add test command
  command! -buffer TestTexLabelsPopup call s:ShowRefPopup()
endfunction

" Check whether some action should be triggered
function! s:TriggerCheck()
  let line = getline('.')
  let col = col('.') - 1

  " Quick check: if no '{' before cursor, return early
  if strridx(strpart(line, 0, col), '{') == -1
    return
  endif

  " Check if cursor is between '{' and '}'
  let open_brace = strridx(line, '{', col - 1)
  let close_brace = strridx(line, '}', col - 1)
  if open_brace < close_brace
      return
  else
      let close_brace = stridx(line, '}', col)
      if close_brace == -1
	  return
      endif
  endif

  " Now the cursor is behide '{', and is before or at '}'.

  " Check if it's a command like \ref, \eqref, and so on
  let before_brace = strpart(line, 0, open_brace)
  if before_brace =~ '\v\\(ref|eqref|pageref)\s*$'
      call s:ShowRefPopup()
  elseif before_brace =~ '\v\\cite\s*$'
      call s:ShowBibPopup()
  elseif before_brace =~ '\v\\(label|tag)\s*$'
      call s:CheckLabels()
  elseif before_brace =~ '\v\\bibitem(\[[^\]]*\])?\s*$'
      call s:CheckBibitems()
  endif
endfunction

" Show the reference popup menu
function! s:ShowRefPopup()
  " Close any existing popup first
  call s:CleanupPopup()

  " Get all available references
  let refs = s:GetAllReferences()
  if empty(refs)
    return
  endif

  " Create popup menu
  let popup_config = {
    \ 'line': winline() + 1,
    \ 'col': wincol(),
    \ 'pos': 'topleft',
    \ 'height': g:tex_labels_popup_height,
    \ 'wrap': 'TRUE',
    \ 'highlight': 'TexLabelsPopup',
    \ 'border': [1, 1, 1, 1],
    \ 'borderhighlight': ['TexLabelsPopupBorder'],
    \ 'title': ' References ',
    \ 'titlehighlight': 'TexLabelsPopupTitle',
    \ 'drag': 'TRUE',
    \ 'scrollbar': 'TRUE',
    \ 'cursorline': 1,
    \ 'zindex': 200,
    \ 'filter': function('s:PopupFilter')
  \ }

  let b:tex_labels_popup = popup_create(refs, popup_config)
endfunction

" Get all references from current buffer
function! s:GetAllReferences()
    let refs = s:RefItems_popup("%")

    let main_file = s:FindMainFile("%")
    let included_files = []

    if strlen(main_file) > 0
	let refs = refs + s:RefItems_popup(main_file)

	let included_files = s:FindIncludedFiles(main_file)
	for file in included_files
	    if simplify(file) != simplify("%")
		let refs = refs + s:RefItems_popup(file)
	    endif
	endfor
    endif

    return refs
endfunction

" Function to generate a List for references
function! s:RefItems_popup(filename)
    let refs = []
    let items = s:ExtractLabelsBibitemsTags(a:filename, "label")

    if !empty(items)
	for i in items
	    let ref_item = s:FormatMenuItem(i)
	    call add(refs, ref_item)
	endfor
    endif

    return refs
endfunction

" Function to extract labels and bibitems from a file, with
"   {type}		'label', 'bibitem' or 'tag'
function! s:ExtractLabelsBibitemsTags(filename, type)
    let items = []

    if a:filename == '%'
	let lines = getbufline('%', 1, '$')
    elseif filereadable(a:filename)
	let lines = readfile(a:filename)
    else
        return items
    endif

    for i in range(len(lines))
        let line = lines[i]
        let line_num = i + 1

        " Remove comments
        let clean_line = substitute(line, '%.*$', '', '')
        if empty(clean_line)
            continue
        endif

        if a:type == 'label'
            " Extract \label commands
            let matches = matchlist(clean_line, '\\label{\([^}]*\)}')
            if len(matches) > 1
                let label = matches[1]
                let item = {
                    \ 'idcode': label,
                    \ 'idnum': '??',
                    \ 'page': '??',
                    \ 'line': line_num,
                    \ 'file': fnamemodify(a:filename, ':t'),
                    \ 'full_path': a:filename
                    \ }
                call add(items, item)
            endif
        elseif a:type == 'bibitem'
            " Extract \bibitem commands
            let matches = matchlist(clean_line, '\\bibitem{\([^}]*\)}')
            if len(matches) > 1
                let bibitem = matches[1]
                let item = {
                    \ 'idcode': bibitem,
                    \ 'idnum': '??',
                    \ 'page': '??',
                    \ 'line': line_num,
                    \ 'file': fnamemodify(a:filename, ':t'),
                    \ 'full_path': a:filename
                    \ }
                call add(items, item)
            endif
        endif
    endfor

    return items
endfunction

" Function to find main file specification
function! s:FindMainFile(filename)
    if !filereadable(a:filename)
        return ''
    endif

    let lines = readfile(a:filename)
    let limit = min([10, len(lines)])

    for i in range(limit)
        let line = lines[i]
        let matches = matchlist(line, '%! Main file:[ \t]*\([^ \t\n\r]*\)')
        if len(matches) > 1
            let main_file = matches[2]
            " Make it absolute path
            if main_file !~ '^/' && main_file !~ '^~' && main_file !~ '^\$'
                let main_file = fnamemodify(a:filename, ':h') . '/' . main_file
            endif
            return simplify(main_file)
        endif
    endfor

    return ''
endfunction

" Function to find included files recursively
function! s:FindIncludedFiles(main_file)
    let included_files = []

    if !filereadable(a:main_file)
        return included_files
    endif

    let lines = readfile(a:main_file)

    for line in lines
        " Remove comments
        let clean_line = substitute(line, '%.*$', '', '')

        " Check for \include and \input
        for cmd in ['include', 'input']
            let matches = matchlist(clean_line, '\\' . cmd . '{\([^}]*\)}')
            if len(matches) > 1
                let included_file = matches[1]
                " Make it absolute path
                if included_file !~ '^/' && included_file !~ '^~' && included_file !~ '^\$'
                    let included_file = fnamemodify(a:main_file, ':h') . '/' . included_file
                endif
                let included_file = simplify(included_file)
                call add(included_files, included_file)

                " Recursively find files in the included file
                let sub_files = s:FindIncludedFiles(included_file)
                call extend(included_files, sub_files)
            endif
        endfor
    endfor

    return included_files
endfunction

" Function to get all relevant files to search
" !!! Not called.
function! s:GetFilesToSearch()
    let files = []
    let current_file = expand('%:p')

    " Always include current file
    call add(files, current_file)

    " Check for main file specification
    let main_file = s:FindMainFile(current_file)
    if !empty(main_file) && filereadable(main_file)
        call add(files, main_file)

        " Add included files
        let included_files = s:FindIncludedFiles(main_file)
        call extend(files, included_files)
    endif

    " Remove duplicates
    let unique_files = []
    for file in files
        if index(unique_files, file) == -1
            call add(unique_files, file)
        endif
    endfor

    return unique_files
endfunction

" Function to format menu item
function! s:FormatMenuItem(item)
    return "(" . a:item.idnum . ")\t{" . a:item.idcode . "} " .
	\ "{page: " . a:item.page . "} {line: " . a:item.line . "} " .
	\ "{file: " . a:item.file . "}"
endfunction

" Show the bibliography popup menu
function! s:ShowBibPopup()
endfunction

" Check duplicated labels
function! s:CheckLabels()
endfunction

" Check duplicated bibitem labels
function! s:CheckBibitems()
endfunction

" Popup filter function
function! s:PopupFilter(winid, key)
    " Store previous key for gg detection
    if !exists('b:prev_popup_key')
        let b:prev_popup_key = ''
    endif

    " Handle different keys
    if a:key == 'n' || a:key == 'j'
        " Move cursor down one line
        call win_execute(a:winid, 'normal! j')
        let b:prev_popup_key = (a:key == 'n' ? 'n' : 'j')
        return 1

    elseif a:key == 'p' || a:key == 'N' || a:key == 'k'
        " Move cursor up one line
        call win_execute(a:winid, 'normal! k')
        let b:prev_popup_key = (a:key == 'p' ? 'p' : (a:key == 'N' ? 'N' : 'k'))
        return 1

    elseif a:key == ' '
        " Scroll one page downward
        "call win_execute(a:winid, 'normal! \<PageDown>')
        call win_execute(a:winid, 'normal! \<C-F>')
        let b:prev_popup_key = ' '
        return 1

    elseif a:key == 'B'
        " Scroll one page backward
        "call win_execute(a:winid, 'normal! \<PageUp>')
        call win_execute(a:winid, 'normal! \<C-B>')
        let b:prev_popup_key = 'B'
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
        let cursor_line = getbufoneline(buf, line('.')[0])
        if !empty(cursor_line)
            " Extract label from the line using the same format as s:FormatMenuItem
            let label = matchstr(cursor_line, '\v\{[^}]+\}')
            " Remove the braces
            let label = substitute(label, '[{}]', '', 'g')
            if !empty(label)
                call s:InsertReference(label)
            endif
        endif
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

" Insert selected reference
function! s:InsertReference(ref)
  let ref_name = matchstr(a:ref, '\v^[^:]+:\s*\zs.*')
  if empty(ref_name)
    return
  endif

  " Find and replace reference in current line
  let line = getline('.')
  let col = col('.') - 1

  " Find brace boundaries
  let start_col = strridx(strpart(line, 0, col), '{') + 1
  let end_col = stridx(line, '}', col)

  " Replace reference and position cursor
  let new_line = strpart(line, 0, start_col) . ref_name . strpart(line, end_col)
  call setline('.', new_line)
  call cursor(line('.'), start_col + len(ref_name))
endfunction

" Clean up popup when leaving buffer
function! s:CleanupPopup()
  if b:tex_labels_popup != -1
    call popup_close(b:tex_labels_popup)
    let b:tex_labels_popup = -1
  endif
endfunction

" Set up highlighting (only once globally)
if !exists('g:tex_labels_highlighted')
  let g:tex_labels_highlighted = 1

  if has('gui_running')
    execute 'highlight TexLabelsPopup guibg=' . g:tex_labels_popup_bg . ' guifg=black'
  else
    let cterm_color = g:tex_labels_popup_bg == 'LightMagenta' ? '219' : (g:tex_labels_popup_bg == 'pink' ? '218' : 'magenta')
    execute 'highlight TexLabelsPopup ctermbg=' . cterm_color . ' ctermfg=0'
  endif

  highlight default TexLabelsPopupBorder guibg=gray guifg=black ctermbg=240 ctermfg=0
  highlight default TexLabelsPopupTitle guibg=darkgray guifg=white ctermbg=238 ctermfg=255
endif

" Initialize the plugin
call s:SetupTexLabels()
