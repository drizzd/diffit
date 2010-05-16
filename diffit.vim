" ============================================================================
" File:        diffit.vim
" Description: Show diff for current buffer
" Maintainer:  Clemens Buchacher <drizzd@aon.at>
" License:     GPLv2
"
" ============================================================================
if exists('loaded_diffit')
    finish
end
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

function s:Die(msg)
	call s:Error('fatal: ' . a:msg)
	throw "diffit"
endfunction

function s:System(...)
	let out = system(join(a:000))
	if v:shell_error
		call s:Die(a:0 . ' failed: ' . out)
	end
	return out
endfunction

function s:Header()
	let header = []
	for n in range(1, line('$'))
			let l = getline(n)
			if l =~ '^diff --git ' ||
						\l =~ '^diff --cc ' ||
						\l =~ '^diff --combined ' ||
						\l =~ '^old mode ' ||
						\l =~ '^new mode ' ||
						\l =~ '^--- ' ||
						\l =~ '^+++ '
				call add(header, l)
				continue
			end
			if l !~ '^index '
				break
			end
	endfor
	return [header, n - 1]
endfunction

function s:Exit()
	let view = b:view
	bdelete
	call winrestview(view)
endfunction

function s:Diffit()
	if exists('b:diffit') && b:diffit == 1
		call s:Exit()
		return
	end
	try
		call s:Diffit_init()
	catch /^diffit$/
		if exists('b:diffit') && b:diffit == 1
			call s:Exit()
		end
	endtry
endfunction

function s:Read_diff(pathlist)
	let diff = tempname()
	let path = ''
	for path in a:pathlist
		let out = s:System('git diff', '--', path, '>', diff)
		if getfsize(diff) > 0
			break
		end
	endfor
	return [diff, path]
endfunction

function s:Write_diff(diff, orig)
	setlocal modifiable
	silent 1,$delete _
	silent exe 'read ' . a:diff
	silent 1delete _
	setlocal nomodifiable

	if a:orig
		let orig_pos = b:view['lnum']
		let new_pos = s:Diffpos(orig_pos)
		let view = copy(b:view)
		let view['lnum'] = abs(new_pos)
		if new_pos > 0
			let view['topline'] += new_pos - orig_pos
			let view['topline'] = max([1, view['topline']])
		else
			let view['topline'] = -new_pos - 4
		end
		let view['curswant'] += 1
		let view['col'] += 1
		call winrestview(view)
	else
		call cursor(abs(s:Diffpos(0)), 1)
	end
endfunction

function s:Diffit_init()
	update
	let out = s:System('git rev-parse',  '--is-inside-work-tree')
	if v:shell_error == 128 || split(out)[0] != 'true'
		call s:Error('not inside work tree')
		return
	elseif v:shell_error
		call s:Error('git rev-parse failed: ' . out)
		return
	end
	let out = s:System('git diff', '--name-only')
	let pathlist = split(out, '\n')
	if empty(pathlist)
		call s:Info('no changes')
		return
	end
	let orig_path = bufname('%')
	let k = index(pathlist, orig_path)
	if k > 0
		call remove(pathlist, k)
		call insert(pathlist, orig_path, 0)
	end
	let [diff, path] = s:Read_diff(pathlist)
	let orig = path == orig_path
	if getfsize(diff) == 0
		call s:Info('no changes')
		return
	end

	let view = winsaveview()
	silent! exe 'edit ' . tempname()
	let b:pathlist = pathlist
	let b:view = view
	let b:diffit = 1
	setf git-diff
	if !exists('b:current_syntax')
		setf diff
	end
	setlocal noswapfile
	setlocal buftype=nofile
	setlocal nowrap
	setlocal foldcolumn=0
	setlocal nobuflisted

	iabc <buffer>

	nnoremap <silent> <buffer> s :call <SID>Stage_hunk(line('.'))<CR>
	nnoremap <silent> <buffer> d :call <SID>Next_diff()<CR>

	call s:Write_diff(diff, orig)
	echon '"' . path . '"'
endfunction

function s:Next_diff()
	call remove(b:pathlist, 0)
	let [diff, path] = s:Read_diff(b:pathlist)
	if getfsize(diff) > 0
		call s:Write_diff(diff, 0)
		echon '"' . path . '"'
	else
		call s:Exit()
	end
endfunction

function s:Diffpos(orig_pos)
	let diffpos = -1
	let hunk_start = 1
	let hunk_end = 1
	call cursor(1, 1)
	while search('^@@', 'W') > 0
		let [start, length] = matchlist(getline('.'),
			\'^@@ -[0-9]*,[0-9]* +\%(\([0-9]*\),\)\?\([0-9]*\)')[1:2]
		if empty(start)
			let start = 1
		end
		if diffpos < 0
			let diffpos = -line('.')
		end
		if start > a:orig_pos
			break
		end
		let diffpos = line('.')
		let hunk_start = start
		let hunk_end = hunk_start + length - 1
	endwhile
	if diffpos < 0
		return diffpos
	end
	let pos = hunk_start - 1
	let target_pos = min([a:orig_pos, hunk_end])
	while diffpos < line('$')
		if getline(diffpos) =~ '^-'
			let diffpos += 1
			continue
		end
		if pos >= target_pos
			break
		end
		let diffpos += 1
		let pos += 1
	endwhile

	if getline(diffpos) =~ '^-'
		return -last
	else
		return diffpos
	end
endfunction

function s:Stage_hunk(pos)
	call cursor(a:pos, 1)
	let h_start = search('^@@', 'bcW')
	if h_start == 0
		return
	end
	call cursor(h_start, 1)
	let h_end = search('^@@', 'nW')-1
	if h_end < 0
		let h_end = line('$')
	end
	let h_range = h_start . ',' . h_end

	let [patch, header_end] = s:Header()
	call extend(patch, getline(h_start, h_end))
	let patchfile = tempname()
	call writefile(patch, patchfile)
	let out = s:System('git apply', '--cached', '--whitespace=nowarn', patchfile)

	setlocal modifiable
	silent exe h_range . 'delete _'
	setlocal nomodifiable
	if line('$') == header_end
		call s:Next_diff()
		return
	end
endfunction

let &cpo = s:old_cpo
