------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Global settings or functions
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local props,editor,menu_cmd=props,editor,scite.MenuCommand
local format,match,char,byte,len,gsub,gmatch,sub=string.format,string.match,string.char,string.byte,string.len,string.gsub,string.gmatch,string.sub
local popen,tonumber=io.popen,tonumber
-- trim functions
local trim=function(str) return match(str,"^%s*(.-)%s*$") end
-- functions for bind global key
local CMD_FMT,cmd_id="command.%s%d.*",0
local bind_global_key=function(key,cmd,subsystem,name)
	cmd_id=cmd_id+1
	props[format(CMD_FMT,"",cmd_id)]=cmd 
	if key then props[format(CMD_FMT,"shortcut.",cmd_id)]=key end
	props[format(CMD_FMT,"subsystem.",cmd_id)]=subsystem or 3
	props[format(CMD_FMT,"name.",cmd_id)]=name or "Command "..cmd_id
	props[format(CMD_FMT,"mode.",cmd_id)]="savebefore:no"
	return cmd_id
end
-- pop-up function
local pop_list=function(len,str,sep)
	if sep then  editor.AutoCSeparator=byte(sep) end
	editor.AutoCAutoHide=false
	editor:AutoCShow(len,str)
end
-- lexer
local make_line_styler=function(f)
	return function(styler)
		local lineStart,lineEnd = editor:LineFromPosition(styler.startPos),editor:LineFromPosition(styler.startPos + styler.lengthDoc)
        editor:StartStyling(styler.startPos, 31)
        for line=lineStart,lineEnd,1 do
			f(line)
        end
	end
end
OnStyle=function(styler)
	local fn=_G[props['Language']]
	if fn then buffer.LEVEL=0; fn(styler) end   
end
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 'On*' functions process low-level events as 'key pressed' or 'char input'
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- process special keyboard event
local TAB= PLATFORM=="windows" and 9 or 65289
OnKey=function(keycode, shift, ctrl, alt)
	if keycode==TAB and (not shift) and (not ctrl) and (not alt) and editor.Focus and editor.SelectionStart==editor.SelectionEnd then 	-- smart 'tab'
		local pos=editor.CurrentPos
		local line=editor:LineFromPosition(pos)
		local sp=buffer.STARTPOS
		if sp then 	-- tab-driven minibuffer
			local action=buffer.ACTION
			if action then return action(sp) end
			return true
		elseif pos==editor:PositionFromLine(line)then -- at beginning of the line, expand or fold
			menu_cmd(IDM_EXPAND)
			return true
		elseif match(char(editor.CharAt[pos-1]),"%w")then -- after a character,  expand the abbreviation 
			menu_cmd(IDM_ABBREV)
			return true
		end
	end					
end
-- enclose braces automatically
local Braces={['[']=']',['\'']='\'',['{']='}',['(']=')',['"']='"'} 
OnChar=function(c)
	c=Braces[c]
	if c and editor.Focus then editor:insert(-1,c) end
end
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Functions for text processing: spell checking and word counting
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local SPELL_WORD_FMT="echo %q | aspell -a"
local SPELL_WORD_PAT="^.-:%s*(.-)%s*$"
suggest_word=function(word,n)
	word=popen(format(SPELL_WORD_FMT,word)):read('*a')
	word=match(word,SPELL_WORD_PAT)
	if word and not editor:AutoCActive() then
		word=gsub(word,", ",char(editor.AutoCSeparator))
		pop_list(n,word)
		return true
	end
end
check_word=function(word)
	local n
	if editor.SelectionStart==editor.SelectionEnd then
		editor:WordLeft();		editor:WordRightEndExtend();
	end
	word=editor:GetSelText()
	n=len(word)
	if n>0 then suggest_word(word,n) end
end
next_error_word=function()
	local E,n=editor.TextLength
	while editor.SelectionEnd<E do
		editor:WordRight();		editor:WordRightEndExtend();
		word=editor:GetSelText()
		n=len(word)
		if suggest_word(word,n) then return end
	end
end
prev_error_word=function()
	local n
	while editor.SelectionStart>0 do
		editor:WordLeft();	editor:WordLeft();		editor:WordRightEndExtend();
		word=editor:GetSelText()
		n=len(word)
		if suggest_word(word,n) then return end
	end
end
bind_global_key(nil,"check_word",3,"Check current word")
bind_global_key(nil,"next_error_word",3,"Next error word")
bind_global_key(nil,"prev_error_word",3,"Previous error word")
-- count words
count_words=function(str)
	str=editor.SelectionStart==editor.SelectionEnd and editor:GetText() or editor:GetSelText()
	local c=0
	for w in gmatch(" "..str,"%s%a+") do print(w) c=c+1 end
	print("Number of Words:",c)
end
bind_global_key(nil,"count_words",3,"Count Words")
-- show all files
local candidate_files=function(filelist)
	if #filelist<1 then return end
	local i=filelist.current or 1
	if i>#filelist then i=1 end
	filelist.current=i
	return filelist[i]
end
local LS_FMT="ls -p %q"
local list_files=function(sp)
	local str=editor:textrange(sp,editor.CurrentPos)
	local cmd=string.format(LS_FMT,string.len(str)>0 and str or "./")
	str=io.popen(cmd):read("*a")
	pop_list(0,str,"\n")
	return true
end
dired_func=function()
	if buffer.STARTPOS then 
		buffer.STARTPOS=nil
		buffer.ACTION=nil
		print("leave dired mode!")
	else
		buffer.STARTPOS=editor.CurrentPos
		buffer.ACTION=list_files
		print("enter dired mode!")
	end
end
bind_global_key("Alt+l","dired_func",3,"dired")

bind_global_key(nil,"ls -p $(CurrentSelection)",0,"List all files")
-- navigation between sentences
move_sentence_ahead=function()
	local pos
	repeat
		editor:WordLeftExtend()
		pos=editor.CurrentPos
	until pos<2 or match(editor:textrange(pos-2,pos),"%s%s")
end
move_sentence_end=function()
	local pos
	local len=editor.Length-2
	repeat
		editor:WordRightEndExtend()
		pos=editor.CurrentPos
	until pos>len or match(editor:textrange(pos,pos+2),"%s%s")
end
bind_global_key("Alt+a","move_sentence_ahead",3,"Move to sentence head")
bind_global_key("Alt+e","move_sentence_end",3,"move to sentence end")
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- lua oriented string execution and evaluation
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Execute or Evaluate a string 
execute_str=function(str)
	if editor.SelectionStart==editor.SelectionEnd then
		str="return "..editor:GetCurLine()
	else
		str=editor:GetSelText()
	end
	print(assert(loadstring(str))())
end
bind_global_key("Alt+x","execute_str",3,"Execute or Evaluate a string")
--  Calculate selection
calculate_selection=function(text)
	local str=""
	local s,e=editor.SelectionNStart,editor.SelectionNEnd
	for i=1,editor.Selections do
		str=str.." "..editor:textrange(s[i-1],e[i-1])
	end
	local sum=0
	for n in gmatch(str,"[%+%-]?0?x?[%da-f]*%.?%d*[eE]?[%+%-]?%d*%.?%d*") do
		sum=sum+(tonumber(n) or 0)
	end
	print(sum)
end
bind_global_key("Alt+z","calculate_selection",3,"Calculate selection")
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--  Functions processing folding and braced blocks
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- out line
local FoldHeadBase=SC_FOLDLEVELHEADERFLAG+SC_FOLDLEVELBASE
local OUTLINE_FMT="%s:%d:%s"
outline=function(line)
	line=editor:LineFromPosition(editor.CurrentPos)
	local foldlevel,filepath=editor.FoldLevel,props['FileNameExt']
	for i=line,editor.LineCount-1 do
		if foldlevel[i]>=FoldHeadBase then print(format(OUTLINE_FMT,filepath,i+1,editor:GetLine(i))) end
	end
end
bind_global_key("Alt+o","outline",3,"Outline")
-- navigation around folds
local get_parent_fold=function(line)
	return editor.FoldLevel[line]>=FoldHeadBase and line or editor.FoldParent[line]
end
prev_fold=function()
	local line,min=editor:LineFromPosition(editor.CurrentPos),0
	local n,l=editor.FoldLevel[line]
	while line>min do
		line=line-1
		if editor.FoldLevel[line]==n then editor:GotoPos(editor:PositionFromLine(line)) return  end
	end
end
next_fold=function()
	local line,max=editor:LineFromPosition(editor.CurrentPos),editor.LineCount-1
	local levels=editor.FoldLevel
	local n=levels[line]
	while line<max do
		line=line+1
		if levels[line]==n then editor:GotoPos(editor:PositionFromLine(line)) return  end
	end
end
select_fold=function()
	local sl=get_parent_fold(editor:LineFromPosition(editor.CurrentPos))
	if sl then 
		local el=editor:GetLastChild(sl,editor.FoldLevel[sl])
		editor:SetSel(editor:PositionFromLine(sl),editor:PositionFromLine(el+1)-1)
	end
end
bind_global_key("Alt+Up","prev_fold",3,"Previous fold")
bind_global_key("Alt+Down","next_fold",3,"Next fold")
bind_global_key("Alt+f","select_fold",3,"Select current fold")
-- brace processing
select_brace=function()
	local pos=editor.CurrentPos
	local to=editor:BraceMatch(pos)
	if to<0 then -- current char is not a brace
		local tag,cur=SCFIND_REGEXP,pos+1
		while cur do
			cur=editor:findtext("[)\\]}]",tag,cur)
			if not cur then  print('Not a valid brace, please move the cursor before the brace to match'); return  end
			to=editor:BraceMatch(cur)
			if to<pos then break end -- is valid
			cur=cur+1
		end
		editor:SetSel(to+1,cur)
	else	
		editor:SetSel(pos,to+1)
	end
end
bind_global_key("Alt+b","select_brace",3,"Select current brace")
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--  Smart text formatting: org-style or gtd-style lines
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local LINE_PAT="^(%s*)()(%S-)(%d*)(%p*)(%s+)()(.-)$"

local SMART_LINE_PAT="^(%s-)(%S-)(%d*)(%p+)(%s+)(.-)$"
local SMART_LINE_PAT="^(%s*)(.-)(%d*)(%p+)(%s*)(.-)$"
smart_next_line=function()
	local pos=editor.CurrentPos
	local start=editor:PositionFromLine(editor:LineFromPosition(pos))
	local str=editor:textrange(start, pos)
--~ 	print(str)
	local s1,t1,n,t2,s2,content=match(str,SMART_LINE_PAT)
--~ 	print(s1,t1,n,t2,s2,content)
	if s1 then
		editor:AddText("\n"..s1..t1..(len(n)>0 and tonumber(n)+1 or n )..t2..s2)
	end
end
bind_global_key("Alt+Enter","smart_next_line",3,"Smart Next line")
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Language specified functions
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- lexer for .gtd files
local GTD_LINE_PAT1="^%s*()%-%s+()%[(%d-)([ X/%%])(%d-)%]()(%s+.-)$"

local gtd_task_done=function(l,c,r)
	return c=='X' or c=='/' and tonumber(l) and l==r
end
local gtd_style_str=function(str,len,ds)
	local ss=1
	for s,e in gmatch(str,"()%b<>()") do
		editor:SetStyling(s-ss, ds)
		editor:SetStyling(e-s, 3)
		ss=e
	end
	if ss<=len then editor:SetStyling(len+1-ss, ds) end
end
local gtd_style_line=function(line)
	local str=editor:GetLine(line)
	if not str then 
		editor.FoldLevel[line]=SC_FOLDLEVELWHITEFLAG+SC_FOLDLEVELBASE
		return 
	end
	local len=string.len(str)
	local level,s,left,center,right,e,text=match(str,GTD_LINE_PAT1)
	if not level then 
		gtd_style_str(str,len,31)
	else
		editor:SetStyling(s-1, 1)
		editor:SetStyling(e-s, gtd_task_done(left,center,right) and 2 or 12 )
		gtd_style_str(text,string.len(text),31)
		level=level-1
	end
	editor.FoldLevel[line]=level and FoldHeadBase+level or SC_FOLDLEVELWHITEFLAG+SC_FOLDLEVELBASE
end
script_gtd=make_line_styler(gtd_style_line)
-- processing lines
local GTD_LINE_PAT2="^(%s*%-%s+%[)(%d-)([ X/%%])(%d-)(%]%s+.-)$"
local gtd_process_line
gtd_process_line=function(line,FoldLevels,has_child)
	if line<0 then return end
	editor:SetSel(editor:PositionFromLine(line),editor.LineEndPosition[line])
	local head,done,op,all,tail=match(editor:GetSelText(),GTD_LINE_PAT2)
	local head1,done1,op1,all1,tail1
	if has_child then
		local level=FoldLevels[line]
		local lastline=editor:GetLastChild(line, level)
		local child_level=level+1
		if lastline<line then return end -- has no child
		done,all=0,0
		for i=line+1,lastline do
			if FoldLevels[i]==child_level then
				head1,done1,op1,all1,tail1=match(editor:GetLine(i),GTD_LINE_PAT2)
				if done1 then
					all=all+1
					if gtd_task_done(done1,op1,all1) then done=done+1 end
				end
			end
		end
		editor:ReplaceSel(head..done.."/"..all..tail) 
	else
		op= op=="X" and " " or "X"
		editor:ReplaceSel(head..op..tail)
	end
	gtd_process_line(editor.FoldParent[line],FoldLevels,true) -- update parent line
end
gtd_toggle_line=function(line)
	local pos=editor.CurrentPos
	line=line and tonumber(line) or editor:LineFromPosition(pos)
	local level=editor.FoldLevel[line]-FoldHeadBase
	if level<0 then return end -- if not a fold line 
	gtd_process_line(line,editor.FoldLevel)
	editor:GotoPos(pos)
end
-- todo: functions processing date or time
local time,difftime,floor=os.time,os.difftime,math.floor
local GTD_DATE_PAT="(%d+)%-(%d+)%-(%d+)"
local GTD_OP_PAT="(%p)(%d+)d"
local GTD_DATE_BLOCK_PAT="%<%s*(%S+)%s*(%S-)%s*%>"
local GTD_TODO_FMT="%s:%d:\t[passed:%d days\tleft:%d days]\t%s"
local ONE_DAY=difftime(time{year=2000,month=1,day=2},time{year=2000,month=1,day=1})
local days_between_dates=function(from,to)
	return floor(difftime(to,from)/ONE_DAY+0.5)
end
local include_today=function(T1,T2)
	if not T1 then return end
	local y,m,d = match(T1,GTD_DATE_PAT)
	local today=time()
	local s=y and days_between_dates(time{year=tonumber(y),month=tonumber(m),day=tonumber(d)},today) or T1=="TODAY" and 0 
	local s1
	if s then
		y,m,d=match(T2,GTD_DATE_PAT)
		if y then 
			s1=days_between_dates(today,time{year=tonumber(y),month=tonumber(m),day=tonumber(d)})
			return s>=0 and s1>=0,s,s1
		end
		y,m,d=match(T2,GTD_OP_PAT)
		if y then
			m=tonumber(m)
			if y=="+" and s>=0 and s<=m then
				return true,s,m-s
			elseif y=="*" and s>=0 and s%m==0 then
				return true,0,0
			elseif y=="-" and s<=0 and s>=-m then
				return true,s+m,-s
			end
		end
		return T2=="" and s==0, 0,0
	end	
end
gtd_get_things_to_do=function()
	local filepath=props['FileNameExt']
	local foldlevel,FoldHeadBase,str=editor.FoldLevel,FoldHeadBase
	output:ClearAll()
	local todo,passed,left
	for line=0,editor.LineCount  do
		if editor.FoldLevel[line]>=FoldHeadBase then
			str=editor:GetLine(line)
			todo,passed,left=include_today(match(str,GTD_DATE_BLOCK_PAT))
			if todo then print(format(GTD_TODO_FMT,filepath,line+1,passed,left,string.match(str,"[^\r\n]*"))) end
		end
	end
end
gtd_insert_current_time=function(line)
	line=line or editor:LineFromPosition(editor.CurrentPos)
	local parent_line=editor.FoldParent[line]
	local time_string=parent_line>=0 and string.match(editor:GetLine(parent_line),GTD_DATE_BLOCK_PAT) or  os.date("%Y-%m-%d")
	editor:insert(-1,string.format("<%s>",time_string))
end

--functions for .org files
local org_style_f=dofile(props["processor.dir.org"].."/lexer.lua")
script_org=make_line_styler(org_style_f)
-- 
local org_search_ref
local org_search_ref=function(path,refs)
	refs=refs or {}
	local f=io.open(path)
	if f then
		local str="\n"..f:read('*a')
		f:close()
		for ref in gmatch(str,"\n%*+([^\n]*)") do
			print(ref)
			if match(ref,"%S") then table.insert(refs,trim(ref)) end
		end
		for file in gmatch(str,"\n@INCLUDE([^\n]*)") do -- search sub files
			if match(file,"%S") then org_search_ref(file,refs) end
		end
	end
	return refs
end

local org_update_ref=function()
	local refs=org_search_ref(props['FileNameExt'],{})
--~ 	table.sort(refs)
	buffer.REFS=table.concat(refs,char(editor.AutoCSeparator))
	return 
end
local org_update_cite=function()
	buffer.CITES=""
	return 
end
org_update=function()
	return op=='cite' and org_update_cite() or org_update_ref()
end
-- 
org_list_ref=function()
	local str=buffer.REFS or org_update_ref()
	pop_list(0,str)
end
org_list_cite=function()
	local str=buffer.CITES or org_update_ref()
	pop_list(0,str)
end
org_up_levels=function()
	local str,s="\n"..editor:GetSelText(),editor.SelectionStart
	str=gsub(str,"(\n%**)(%*)","%1")
	str=sub(str,2)
	editor:ReplaceSel(str)
	editor:SetSel(s,s+len(str))
end
org_down_levels=function()
	local str,s="\n"..editor:GetSelText(),editor.SelectionStart
	str=gsub(str,"(\n%**)(%*)","%1%2%*")
	str=sub(str,2)
	editor:ReplaceSel(str)
	editor:SetSel(s,s+len(str))
end

-- init editor's AutoCSeparator while  open any file
OnOpen=function(path)
	editor.AutoCSeparator=string.byte("\n") 
end
