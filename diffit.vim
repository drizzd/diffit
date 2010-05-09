" ============================================================================
" File:        diffit.vim
" Description: Show diff for current buffer
" Maintainer:  Clemens Buchacher <drizzd@aon.at>
" License:     GPLv2
"
" ============================================================================
if exists('loaded_diffit')
    finish
endif
let loaded_diffit = 1

let s:diffit_version = '0'

"for line continuation - i.e dont want C in &cpo
let s:old_cpo = &cpo
set cpo&vim

map <silent> <Leader>d :call <SID>Diffit()<CR>

function s:Error(msg)
	echohl ErrorMsg
	echon 'diffit: ' . a:msg
	echohl None
endfunction

function s:Info(msg)
	echon 'diffit: ' . a:msg
endfunction

function s:Header()
	let header = []
	for n in range(1, line('$'))
			let l = getline(n)
			if l =~ '^diff --git ' ||
						\l =~ '^diff --cc ' ||
						\l =~ '^diff --combined ' ||
						\l =~ '^--- ' ||
						\l =~ '^+++ '
				call add(header, l)
				continue
			endif
			if l !~ '^index '
				break
			end
	endfor
	return [header, n - 1]
endfunction

function s:Diffit()
	if exists('b:diffit') && b:diffit == 1
		let view = b:view
		bdelete
		call winrestview(view)
		return
	endif

	update
	let out = system('git rev-parse --is-inside-work-tree')
	if v:shell_error == 128 || split(out)[0] != 'true'
		call s:Error('not inside work tree')
		return
	elseif v:shell_error
		call s:Error('git rev-parse failed: ' . out)
		return
	end
	let diff = tempname()
	let out = system('git diff -- ' . bufname('%') . ' > ' . diff)
	if v:shell_error
		call s:Error('git diff failed: ' . out)
		return
	end
	if getfsize(diff) == 0
		call s:Info('no changes')
		return
	end

	let view = winsaveview()
	silent! exe 'edit ' . tempname()
	let b:diffit = 1
	setf git-diff
	setlocal noswapfile
	setlocal buftype=nofile
	setlocal nowrap
	setlocal foldcolumn=0
	setlocal nobuflisted

	iabc <buffer>

	nnoremap <silent> <buffer> s :call <SID>Stage_hunk(line('.'))<CR>

	silent exe 'read ' . diff
	silent 1delete _
	setlocal nomodifiable

	let b:view = copy(view)
	let orig_pos = view['lnum']
	let new_pos = s:Diffpos(orig_pos)
	let view['lnum'] = abs(new_pos)
	if new_pos > 0
		let view['topline'] += new_pos - orig_pos
		let view['topline'] = max([1, view['topline']])
	else
		let view['topline'] = -new_pos - 4
	endif
	let view['curswant'] += 1
	let view['col'] += 1
	call winrestview(view)
endfunction

function s:Diffpos(orig_pos)
	let diffpos = -1
	let hunk_start = 1
	let hunk_end = 1
	call cursor(1, 1)
	while search('^@@', 'W') > 0
		let [start, length] = matchlist(getline('.'),
			\'^@@ -[0-9]*,[0-9]* +\([0-9]*\),\([0-9]*\)')[1:2]
		if diffpos < 0
			let diffpos = -line('.')
		end
		if start > a:orig_pos
			break
		endif
		let diffpos = line('.') + 1
		let hunk_start = start
		let hunk_end = hunk_start + length - 1
	endwhile
	if diffpos < 0
		return diffpos
	endif
	let pos = hunk_start
	let target_pos = min([a:orig_pos, hunk_end])
	while diffpos < line('$')
		if getline(diffpos) =~ '^-'
			let diffpos += 1
			continue
		endif
		if pos >= target_pos
			break
		endif
		let diffpos += 1
		let pos += 1
	endwhile

	return diffpos
endfunction

function s:Stage_hunk(pos)
	call cursor(a:pos, 1)
	let h_start = search('^@@', 'bcW')
	if h_start == 0
		return
	endif
	call cursor(h_start, 1)
	let h_end = search('^@@', 'nW')-1
	if h_end < 0
		let h_end = line('$')
	endif
	let h_range = h_start . ',' . h_end

	let [patch, header_end] = s:Header()
	call extend(patch, getline(h_start, h_end))
	let patchfile = tempname()
	call writefile(patch, patchfile)
	let git_apply = 'git apply --cached --whitespace=nowarn'
	let out = system(git_apply . ' ' . patchfile)
	if v:shell_error
		call s:Error('git apply failed: ' . out)
		return
	endif

	setlocal modifiable
	silent exe h_range . 'delete _'
	if line('$') == header_end
		bdelete
		return
	end
	setlocal nomodifiable
endfunction

let &cpo = s:old_cpo
