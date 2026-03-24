# Quick Usage Guide

## Getting Started

### Basic Setup
1. Install the plugin (see README.md for instructions)
2. Open a LaTeX file in Vim
3. Start typing a reference command

### First Usage
```latex
\ref{  " Popup menu will appear here
```

## Common Scenarios

### Scenario 1: Simple Document
```latex
\documentclass{article}

\begin{document}

\section{Introduction}
\label{sec:intro}
This is the introduction.

\section{Conclusion}
\label{sec:conclusion}
See Section~\ref{<cursor here> for details.

\end{document}
```

When you type `\ref{`, a popup appears showing:
```
 Label items
┌─────────────────────────────────────┐
│ (section: 1.1)    {sec:intro}       │
│ (section: 1.2)    {sec:conclusion}  │
└─────────────────────────────────────┘
```

### Scenario 2: Multi-file Project
```latex
% main.tex
%! Main file: main.tex

\documentclass{book}

\include{chapter1}
\include{chapter2}
```

```latex
% chapter1.tex
\chapter{Introduction}
\label{ch:intro}

\section{Background}
\label{sec:bg}
```

```latex
% chapter2.tex
\chapter{Methods}
\label{ch:methods}

As discussed in Chapter~\ref{<cursor here>...
```

The popup shows labels from both chapters:
```
 Label items
┌─────────────────────────────────────┐
│ (chapter: 1)      {ch:intro}        │
│ (section: 1.1)    {sec:bg}          │
│ (chapter: 2)      {ch:methods}      │
└─────────────────────────────────────┘
```

### Scenario 3: Many Labels (Counter Organization)
When you have many labels, the plugin offers organized browsing:

1. When popup limit is exceeded, you'll see:
```
 List by files or by counters
┌─────────────────────────────────────-┐
│ [1] List all labels anyway           │
│ [2] Select according to files        │
│ [3] Select according to counters     │
│ [4] Select through "file -> counter" │
│ [5] Select through "counter -> file" │
└─────────────────────────────────────-┘
```

2. Choose "Select according to counters":
```
 Search labels according to LaTeX counters
┌─────────────────────────────────────┐
│ chapter                             │
│ equation                            │
│ figure                              │
│ section                             │
└─────────────────────────────────────┘
```

3. Select a counter to see related labels only.

## Navigation Examples

### Basic Navigation
- `j` or `n` - Move down
- `k` or `p` - Move up
- `Enter` - Select item

### Fast Navigation
- `5j` - Move down 5 lines
- `G` - Go to last item
- `gg` - Go to first item

### Page Navigation
- `Space` or `Ctrl+F` - Page down
- `b` or `Ctrl+B` - Page up

## Troubleshooting Tips

### Popup Not Appearing?
1. Check file type: `:set ft?` should show `tex`
2. Verify popup support: `:echo has('popup')` should be `1`
3. Test with command: `:TestTexLabelsPopup`

### References Not Found?
1. Compile your LaTeX document first
2. Check for main file specification
3. Verify labels are properly defined

### Performance Issues?
1. Reduce `g:tex_labels_limit` in your vimrc
2. Use main file specifications
3. Consider splitting large documents

## Keyboard Reference

| Key | Action |
|-----|--------|
| `Enter` | Select reference |
| `j`/`n` | Move down |
| `k`/`p`/`N` | Move up |
| `Space`/`Ctrl+F` | Page down |
| `b`/`Ctrl+B` | Page up |
| `G` | Go to last item |
| `gg` | Go to first item |
| `Esc` | Close popup |

## Configuration Examples

### Basic Configuration
```vim
" Set popup appearance
let g:tex_labels_popup_bg = 'lightblue'
let g:tex_labels_popup_height = 10
let g:tex_labels_limit = 25
```

### Advanced Configuration
```vim
" For very large projects
let g:tex_labels_limit = 100
let g:tex_labels_mainfile_scope = 20

" For smaller screens
let g:tex_labels_popup_height = 6
```

## Best Practices

### For Single Documents
- Use descriptive label names: `\label{fig:results}` instead of `\label{fig1}`
- Compile document before using plugin
- Use popup navigation for quick selection

### For Multi-file Projects
- Add main file specification to root document
- Use consistent naming conventions across files
- Regularly compile to keep auxiliary files current

### For Large Documents
- Use counter-based organization
- Consider splitting into smaller files
- Adjust limits and popup settings for better performance

## Frequently Asked Questions

**Q: Why don't I see my references?**
A: Make sure you've compiled your LaTeX document to generate .aux files.

**Q: How do I work with included files?**
A: The plugin automatically discovers included files. Add `%! Main file: main.tex` to specify the main document.

**Q: Can I customize the popup appearance?**
A: Yes, use `g:tex_labels_popup_bg` and related configuration options.

**Q: What if I have too many labels?**
A: The plugin will offer counter-based or file-based organization when limits are exceeded.

**Q: How do I avoid duplicate labels?**
A: The plugin automatically detects and warns about duplicate labels as you type.
