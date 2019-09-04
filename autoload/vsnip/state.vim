function! vsnip#state#create(snippet) abort
  let l:state = {
        \ 'running': v:false,
        \ 'buffer': [],
        \ 'start_position': vsnip#utils#curpos(),
        \ 'lines': [],
        \ 'current_idx': -1,
        \ 'placeholders': [],
        \ }

  " create body
  let l:indent = vsnip#utils#get_indent()
  let l:indent_level = vsnip#utils#get_indent_level(getline('.'), l:indent)
  let l:body = join(a:snippet['body'], "\n")
  let l:body = substitute(l:body, "\t", l:indent, 'g')
  let l:body = substitute(l:body, "\n", "\n" . repeat(l:indent, l:indent_level), 'g')
  let l:body = substitute(l:body, "\n\\s\\+\\ze\n", "\n", 'g')

  " resolve variables.
  let l:body = vsnip#syntax#variable#resolve(l:body)

  " resolve placeholders.
  let [l:body, l:placeholders] = vsnip#syntax#placeholder#resolve(l:state['start_position'], l:body)
  let l:state['placeholders'] = l:placeholders
  let l:state['lines'] = split(l:body, "\n", v:true)

  return l:state
endfunction

function! vsnip#state#sync(state, diff) abort
  if !s:is_valid_diff(a:diff)
    return [a:state, []]
  endif

  if !s:is_diff_in_snippet_range(a:state, a:diff)
    let a:state['running'] = v:false
    return [a:state, []]
  endif

  " update snippet lines.
  let a:state['lines'] = vsnip#utils#edit#replace_text(
        \   a:state['lines'],
        \   vsnip#utils#range#relative(a:state['start_position'], a:diff['range']),
        \   a:diff['lines']
        \ )

  let l:placeholders = vsnip#syntax#placeholder#by_order(a:state['placeholders'])

  " fix placeholder ranges after already modified placeholder.
  let l:target = {}
  let l:i = 0
  let l:j = len(l:placeholders)
  while l:i < len(l:placeholders)
    let l:p = l:placeholders[l:i]

    " relocate same lines.
    if !empty(l:target)
      if l:p['range']['start'][0] == l:target['range']['start'][0]
        let l:p['range']['start'][1] += l:shiftwidth
        let l:p['range']['end'][1] += l:shiftwidth
      else
        break
      endif
    endif

    " modified placeholder.
    if vsnip#utils#range#in(l:p['range'], a:diff['range'])
      let l:new_lines = vsnip#utils#edit#replace_text(
            \   split(l:p['text'], "\n", v:true),
            \   vsnip#utils#range#relative(l:p['range']['start'], a:diff['range']),
            \   a:diff['lines']
            \ )
      let l:new_text = join(l:new_lines, "\n")

      " TODO: support multi-line.
      let l:old_length = l:p['range']['end'][1] - l:p['range']['start'][1]
      let l:new_length = strlen(l:new_text)
      let l:shiftwidth = l:new_length - l:old_length
      let l:p['text'] = l:new_text
      let l:p['range']['end'][1] += l:shiftwidth
      let l:target = l:p
      let l:j = l:i + 1
    endif

    let l:i += 1
  endwhile

  " sync same tabstop placeholder.
  let l:in_sync = {}
  let l:edits = []
  while l:j < len(l:placeholders)
    let l:p = l:placeholders[l:j]

    let l:is_same_line_in_sync = !empty(l:in_sync) && l:p['range']['start'][0] == l:in_sync['range']['start'][0]

    if l:p['tabstop'] == l:target['tabstop']
      call add(l:edits, {
            \   'range': deepcopy(l:p['range']),
            \   'lines': l:new_lines
            \ })
      let l:p['text'] = l:target['text']
      let l:p['range']['end'][1] += l:shiftwidth
      let l:in_sync = l:p
    endif

    if l:is_same_line_in_sync
      let l:p['range']['start'][1] += l:shiftwidth
      let l:p['range']['end'][1] += l:shiftwidth
    endif

    let l:j += 1
  endwhile

  return [a:state, l:edits]
endfunction

function! s:is_valid_diff(diff) abort
  let l:has_range_length = vsnip#utils#range#has_length(a:diff['range'])
  let l:has_new_text = len(a:diff['lines']) > 1 || get(a:diff['lines'], 0, '') !=# ''
  return vsnip#utils#range#valid(a:diff['range']) && l:has_range_length || l:has_new_text
endfunction

function! s:is_diff_in_snippet_range(state, diff) abort
  let l:snippet_text = join(a:state['lines'], "\n")
  let l:snippet_range = {
        \   'start': a:state['start_position'],
        \   'end': vsnip#utils#text_index2buffer_pos(a:state['start_position'], strlen(l:snippet_text), l:snippet_text)
        \ }
  return vsnip#utils#range#in(l:snippet_range, a:diff['range'])
endfunction

