" tex-labels.vim - Handle labels, bibitems and tags in LaTeX files
" Maintainer:   Bin Zhou
" Version:      0.1
" Upgraded on: 
" Last change: Thu 2025-10-09 02:08:15 CST (+0800)

" Only load this plugin once
if exists('g:loaded_tex_labels')
  finish
endif
let g:loaded_tex_labels = 1

" Global variable to track current popup
let s:current_popup = -1

" Configuration options
if !exists('g:tex_labels_popup_bg')
  let g:tex_labels_popup_bg = 'pink'
endif

if !exists('g:tex_labels_popup_height')
  let g:tex_labels_popup_height = 6
endif

" File type detection
augroup TexLabels
  autocmd!
  autocmd FileType tex,texplaintex,latex call s:SetupTexLabels()
augroup END

" Setup function for TeX files
function! s:SetupTexLabels()
  echom "TexLabels: Setting up for TeX file"

  " Set up popup trigger when entering insert mode
  autocmd InsertEnter <buffer> call s:TriggerPopupOnInsertEnter()

  " Add test command
  command! -buffer TestTexLabelsPopup call s:ShowRefPopup()

  echom "TexLabels: Setup complete"
endfunction

" Trigger popup when entering insert mode
function! s:TriggerPopupOnInsertEnter()
  let line = getline('.')
  let col = col('.') - 1

  echom "TexLabels: Entered insert mode at col " . col

  " Only trigger if cursor is inside reference command braces
  if s:IsInsideRefCommand(line, col)
    echom "TexLabels: Cursor inside ref command, showing popup"
    call s:ShowRefPopup()
  else
    echom "TexLabels: Cursor not inside ref command"
  endif
endfunction

" Check if cursor is inside a reference command (between the braces)
function! s:IsInsideRefCommand(line, col)
  " Find the opening brace before cursor position
  let open_brace = strridx(strpart(a:line, 0, a:col), '{')
  if open_brace == -1
    return 0
  endif

  " Find closing brace after cursor position
  let close_brace = stridx(a:line, '}', a:col)
  if close_brace == -1
    " No closing brace found, check if there's text after opening brace
    if a:col <= open_brace
      return 0
    endif
  endif

  " Look for the command before the opening brace
  let before_brace = strpart(a:line, 0, open_brace)

  " Check for ref, eqref, pageref, cite commands immediately before the brace
  if before_brace =~ '\v\\(ref|eqref|pageref|cite)\s*$'
    echom "TexLabels: Inside ref command braces"
    return 1
  endif

  return 0
endfunction


" Show the reference popup menu
function! s:ShowRefPopup()
  echom "TexLabels: ShowRefPopup called"
  " Close any existing popup first
  if s:current_popup != -1 && popup_exists(s:current_popup)
    call popup_close(s:current_popup)
    let s:current_popup = -1
  endif

  " Get all available references
  let refs = s:GetAllReferences()
  echom "TexLabels: Found " . len(refs) . " references"

  if len(refs) == 0
    echom "TexLabels: No references found, not showing popup"
    return
  endif

  " Create popup menu positioned below cursor
  let popup_config = {
    \ 'line': winline() + 1,
    \ 'col': wincol(),
    \ 'pos': 'botleft',
    \ 'height': g:tex_labels_popup_height,
    \ 'wrap': 0,
    \ 'highlight': 'TexLabelsPopup',
    \ 'border': [1, 1, 1, 1],
    \ 'borderhighlight': ['TexLabelsPopupBorder'],
    \ 'title': ' References ',
    \ 'titlehighlight': 'TexLabelsPopupTitle',
    \ 'zindex': 200,
    \ 'fixed': 0
  \ }

  " Create the popup
  let winid = popup_create(refs, popup_config)
  let s:current_popup = winid

  " Set up key mappings for the popup
  call popup_setoptions(winid, {
    \ 'filter': function('s:PopupFilter'),
    \ 'callback': function('s:PopupCallback')
  \ })
endfunction

" Get all references from current file and included files
function! s:GetAllReferences()
  let refs = []

  " Get labels from current buffer
  call s:ExtractLabels('', refs)

  " Get bibitems from current buffer
  call s:ExtractBibitems('', refs)

  " Get tags from current buffer
  call s:ExtractTags('', refs)

  " Remove duplicates and sort
  let refs = sort(uniq(refs))

  return refs
endfunction

" Extract labels from buffer
function! s:ExtractLabels(filename, refs)
  let lines = getbufline(a:filename == '' ? '%' : a:filename, 1, '$')

  for line in lines
    let label = matchstr(line, '\\label{\zs[^}]*\ze}')
    if label != ''
      call add(a:refs, 'label: ' . label)
    endif
  endfor
endfunction

" Extract bibitems from buffer
function! s:ExtractBibitems(filename, refs)
  let lines = getbufline(a:filename == '' ? '%' : a:filename, 1, '$')

  for line in lines
    let bibitem = matchstr(line, '\\bibitem{\zs[^}]*\ze}')
    if bibitem != ''
      call add(a:refs, 'bib: ' . bibitem)
    endif
  endfor
endfunction

" Extract tags from buffer
function! s:ExtractTags(filename, refs)
  let lines = getbufline(a:filename == '' ? '%' : a:filename, 1, '$')

  for line in lines
    let tag = matchstr(line, '\\tag{\zs[^}]*\ze}')
    if tag != ''
      call add(a:refs, 'tag: ' . tag)
    endif
  endfor
endfunction

" Popup filter function
function! s:PopupFilter(winid, key)
  " Handle navigation keys
  if a:key == "\<CR>"
    " Select the current item
    let line = getbufline(winbufnr(a:winid), line('.'))
    if !empty(line)
      call s:InsertReference(line[0])
    endif
    let s:current_popup = -1
    return popup_close(a:winid)
  elseif a:key == "\<Esc>"
    " Close popup without selection
    let s:current_popup = -1
    return popup_close(a:winid)
  elseif a:key == "\<Up>" || a:key == "\<Down>" || a:key == "\<PageUp>" || a:key == "\<PageDown>"
    " Let popup handle navigation
    return 0
  else
    " Filter characters - close popup on any other key
    let s:current_popup = -1
    return popup_close(a:winid)
  endif
endfunction

" Popup callback function
function! s:PopupCallback(winid, result)
  " Handle popup completion if needed
endfunction

" Insert selected reference
function! s:InsertReference(ref)
  " Extract just the reference name (remove type prefix)
  let ref_name = matchstr(a:ref, '\v^[^:]+:\s*\zs.*')

  " Replace current reference with the selected one
  let line = getline('.')
  let col = col('.') - 1

  " Find the start of the current reference
  let start_col = col
  while start_col > 0 && line[start_col-1] != '{'
    let start_col -= 1
  endwhile

  " Find the end of the current reference
  let end_col = col
  while end_col < len(line) && line[end_col] != '}'
    let end_col += 1
  endwhile

  " Replace the reference
  let new_line = strpart(line, 0, start_col + 1) . ref_name . strpart(line, end_col)
  call setline('.', new_line)

  " Position cursor after the reference
  call cursor(line('.'), start_col + 1 + len(ref_name))
endfunction

" Set up highlighting
highlight default TexLabelsPopup guibg=g:tex_labels_popup_bg guifg=black
highlight default TexLabelsPopupBorder guibg=gray guifg=black
highlight default TexLabelsPopupTitle guibg=darkgray guifg=white

" Set the actual background color
execute 'highlight TexLabelsPopup guibg=' . g:tex_labels_popup_bg
