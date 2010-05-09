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

function s:Diffit()
	if exists('b:diffit') && b:diffit == 1
		bdelete
		return
	endif

	update
	let out = system('git rev-parse --is-inside-work-tree')
	if v:shell_error == 128 || out !~ '^true'
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

	silent! exe 'edit ' . tempname()
	let b:diffit = 1
	"let view = winsaveview()
	setf git-diff
	setlocal noswapfile
	setlocal buftype=nofile
	setlocal nowrap
	setlocal foldcolumn=0
	setlocal nobuflisted

	iabc <buffer>

	nnoremap <silent> <buffer> s :call <SID>Stage_hunk()<CR>

	silent exe 'read ' . diff
	silent 1delete _
	setlocal nomodifiable
endfunction

function s:Stage_hunk()
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

	let patch = tempname()
	" FIXME: truncate patch
	for n in range(1, line('$'))
			let l = getline(n)
			if l =~ '^diff --git ' ||
						\l =~ '^diff --cc ' ||
						\l =~ '^diff --combined ' ||
						\l =~ '^--- ' ||
						\l =~ '^+++ '
				silent exe ':' . n 'write! >> ' . patch
				continue
			endif
			if l !~ '^index '
				break
			end
	endfor
	let header_end = n - 1

	silent exe h_range . 'write >> ' . patch
	let git_apply = 'git apply --cached --whitespace=nowarn'
	let out = system(git_apply . ' ' . patch)
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
