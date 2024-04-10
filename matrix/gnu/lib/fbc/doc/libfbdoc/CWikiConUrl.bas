''  fbdoc - FreeBASIC User's Manual Converter/Generator
''	Copyright (C) 2006-2022 The FreeBASIC development team.
''
''	This program is free software; you can redistribute it and/or modify
''	it under the terms of the GNU General Public License as published by
''	the Free Software Foundation; either version 2 of the License, or
''	(at your option) any later version.
''
''	This program is distributed in the hope that it will be useful,
''	but WITHOUT ANY WARRANTY; without even the implied warranty of
''	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
''	GNU General Public License for more details.
''
''	You should have received a copy of the GNU General Public License
''	along with this program; if not, write to the Free Software
''	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02111-1301 USA.


'' CWikiConUrl
''
'' chng: apr/2006 written [v1ctor]
'' chng: sep/2006 updated [coderJeff]
''       dec/2006 updated [coderJeff] - using classes
''

#include once "CHttp.bi"
#include once "CHttpForm.bi"
#include once "CHttpStream.bi"
#include once "CWikiConUrl.bi"
#include once "fbdoc_string.bi"
#include once "printlog.bi"

namespace fb.fbdoc

	type CWikiConUrlCtx_
		as CHttp ptr		http
		as zstring ptr		url
		as zstring ptr		ca_file
		as zstring ptr		pagename
		as integer			pageid
		as string csrftoken
		declare function queryCsrfTokenString( ) as string
		declare function queryCsrfToken( byval force as boolean = TRUE ) as boolean
		declare sub maybeAddCsrfTokenToForm( byval form as CHttpForm ptr )
	end type

	const wakka_prefix = "?wakka="
	const wakka_loginpage = "UserSettings"
	const wakka_raw = "/raw"
	const wakka_rawlist = "/rawlist"
	const wakka_rawlist_index = "/rawlist&format=index"
	const wakka_edit = "/edit"
	const wakka_getid = "/getid"
	const wakka_error = "wiki-error"
	const wakka_response = "wiki-response"

	'':::::
	private function build_url _
		( _
			byval ctx as CWikiConUrlCtx ptr, _
			byval page as zstring ptr = NULL, _
			byval method as zstring ptr = NULL _
		) as string

		dim as string url

		url = *ctx->url + wakka_prefix

		if( page = NULL ) then
			page = ctx->pagename 
		end if

		url += *page

		if( method <> NULL ) then
			url += *method
		end if

		function = url

	end function

	private function strIsAlphaNumOnly( byref token as string ) as boolean
		for i as integer = 0 to len( token ) - 1
			select case as const( token[i] )
			case asc( "a" ) to asc( "z" ), _
			     asc( "A" ) to asc( "Z" ), _
			     asc( "0" ) to asc( "9" )
			case else
				return FALSE
			end select
		next
		return TRUE
	end function

	'' Extract the CSRFToken value embedded in a UserSettings html page (or
	'' rather, the Login form on it) generated by Wikka
	private function extractCsrfToken( byref htmlpage as string ) as string
		const CSRFTokenHead = "<input type=""hidden"" name=""CSRFToken"" value="""
		const CSRFTokenLength = 40 '' Wikka uses a 40-byte SHA1 hash

		var headbegin = instr( htmlpage, CSRFTokenHead )
		if( headbegin <= 0 ) then
			printlog "(error: CSRFToken not found)", TRUE
			return ""
		end if

		var token = mid( htmlpage, headbegin + len( CSRFTokenHead ), CSRFTokenLength )
		if( strIsAlphaNumOnly( token ) = FALSE ) then
			printlog "(error: invalid CSRFToken: " + token + ")", TRUE
			return ""
		end if

		return token
	end function

	function CWikiConUrlCtx.queryCsrfTokenString( ) as string
		dim stream as CHttpStream = CHttpStream( http )
		if( stream.Receive( build_url( @this, wakka_loginpage ), TRUE, ca_file ) = FALSE ) then
			return ""
		end if
		return extractCsrfToken( stream.Read() )
	end function

	function CWikiConUrlCtx.queryCsrfToken( byval force as boolean = TRUE ) as boolean
		if( (len( csrftoken ) = 0) orelse (force = TRUE) ) then
			csrftoken = queryCsrfTokenString( )
			if( len( csrftoken ) = 0 ) then
				return FALSE
			end if
		end if
		return TRUE
	end function

	sub CWikiConUrlCtx.maybeAddCsrfTokenToForm( byval form as CHttpForm ptr )
		if( len( csrftoken ) > 0 ) then
			form->Add( "CSRFToken", csrftoken )
		end if
	end sub

	'':::::
	static sub CWikiConUrl.GlobalInit()
		CHttp.GlobalInit()
	end sub

	'':::::
	constructor CWikiConUrl _
		( _
			byval url as zstring ptr, _
			byval ca_file as zstring ptr = NULL _
		)

		ctx = new CWikiConUrlCtx
  
  		ctx->http = new CHttp
		ZSet @ctx->url, url
		if( ca_file ) then
			ZSet @ctx->ca_file, ca_file
		else
			ctx->ca_file = NULL
		end if

  		ctx->pagename = NULL
  		ctx->pageid = 0
		
	end constructor

	'':::::
	destructor CWikiConUrl _
		( _
		)

		if( ctx = NULL ) then
			exit destructor
		end if
		ZFree @ctx->pagename
		ZFree @ctx->ca_file
		ZFree @ctx->url

		if( ctx->http <> NULL ) then
			delete ctx->http
			ctx->http = NULL
		end if

		delete ctx

	end destructor

	'':::::
	private function check_iserror _
		( _
			byval body as zstring ptr _
		) as integer

		if( len( *body ) = 0 ) then
			return TRUE
		end if

		function = ( instr( 1, *body, "<" + wakka_error + ">" ) > 0 )
		
	end function

	'':::::
	function CWikiConUrl.Login _
		( _
			byval username as zstring ptr, _
			byval password as zstring ptr _
		) as boolean

		if( ctx = NULL ) then
			return FALSE
		end if

		if( ctx->queryCsrfToken( ) = FALSE ) then
			return FALSE
		end if

		dim as CHttpForm ptr form

		form = new CHttpForm
		if( form = NULL ) then
			return FALSE
		end if

		form->Add( "action", "login" )
		form->Add( "wakka", "UserSettings" )
		form->Add( "name", username )
		form->Add( "password", password )
		form->Add( "submit", "Login" )
		ctx->maybeAddCsrfTokenToForm( form )

		dim as string response = ctx->http->Post( build_url( ctx, wakka_loginpage ), form, ctx->ca_file )

		function = ( check_iserror( response ) = FALSE )

		delete form

	end function

	'':::::
	private function get_response _
		( _
			byval body as zstring ptr _
		) as string
		
		dim as string res
		dim as integer ps, pe, lgt, i
		
		function = ""
		
		if( len( *body ) = 0 ) then
			exit function
		end if
		
		ps = instr( 1, *body, "<" + wakka_response + ">" )
		if( ps = 0 ) then
			exit function
		end if

		pe = instr( ps, *body, "</" + wakka_response + ">" )
		if( pe = 0 ) then
			exit function
		end if
		
		ps -= 1
		pe -= 1
		
		ps += 1 + len( wakka_response ) + 1
		lgt = ((pe - 1) - ps) + 1
		res = space( lgt )
		i = 0
		do while( i < lgt )
			res[i] = body[ps+i]
			i += 1
		loop
		
		function = res
		
	end function

	'':::::
	private sub remove_http_headers( byref body as string )

		dim as integer i = 1, n = len(body)
		const whitespace = chr(9,10,13,32)
		const crlfcrlf = chr(13,10,13,10)

		while( i <= n )
			if instr(whitespace,mid(body, i, 1)) = 0 then
				exit while
			end if
			i += 1
		wend

		if ( i < n ) then
			if( mid(body, i, 5) = "HTTP/" ) then
				i = instr( i, body, crlfcrlf )
				if( i > 0 ) then
					body = mid( body, i + 4 )
				end if

			end if
		end if

	end sub

	'':::::
	private sub remove_trailing_whitespace( byref body as string )

		dim as integer i, n = len(body)
		const whitespace = chr(9,10,13,32)

		i = n
		while( i >= 1 )
			if instr(whitespace,mid(body, i, 1)) = 0 then
				exit while
			end if
			i -= 1
		wend

		if( i < n ) then
			if( i > 0 ) then
				body = left( body, i )
			else
				body = chr(10)
			end if
		end if

	end sub

	''
	private sub remove_html_tags _
		( _
			byref sBody as string _
		)

		'' remove HTML tags	from PageIndex

		dim as string txt, html
		dim as integer n, b = 0, j = 1, atag = 0, i
		n = len(sBody)
		txt = ""

		while( i <= n )

			if( lcase(mid( sBody, i, 4 )) = "&lt;" ) then
				txt += "<"
				i += 4
			elseif( lcase(mid( sBody, i, 4 )) = "&gt;" ) then
				txt += ">"
				i += 4
			elseif( lcase(mid( sBody, i, 5 )) = "&amp;" ) then
				txt += "&"
				i += 5
			elseif( lcase(mid( sBody, i, 6 )) = "&nbsp;" ) then
				txt += " "
				i += 6
			elseif( mid( sBody, i, 4 ) = "All<" and atag = 1 ) then
				txt += "All" + crlf + "----" + crlf
				i += 3
			elseif( mid( sBody, i, 5 ) = "All <" and atag = 1 ) then
				txt += "All " + crlf + "----" + crlf
				i += 3
			elseif( lcase(mid( sBody, i, 1 )) = "<" ) then
				atag = 0
				b = 1
				j = i + 1
				while( j <= n and b > 0 )
					select case ( mid( sBody, j, 1 ))
					case "<"
						b += 1
						j += 1
					case ">"
						b -= 1
						j += 1
					case chr(34)
						j += 1
						while( j <= n )
							select case ( mid( sBody, j, 1 ))
							case chr(34)
								j += 1
								exit while
							case else
								j += 1
							end select
						wend
					case else
						j += 1
					end select
				wend 

				html = mid( sBody, i, j - i )
				select case lcase( html )
				case "<br>","<br />"
					txt += crlf
				case "<hr>","<hr />"
					txt += "----"
				case else
					if left( html, 3 ) = "<a " then
						atag = 2
					end if
				end select
				i = j

			else
				txt += mid( sBody, i, 1 )
				i += 1
			end if

			if( atag = 2 ) then
				atag = 1
			else
				atag = 0
			end if

		wend

		sBody = txt

	end sub

	''
	private sub extract_page_names _
		( _
			byref sBody as string _
		)

		dim as string txt = ""
		dim as integer i = any, i0 = 0
		dim as integer n = len(sBody)
		dim as boolean bFirstMark = false
		dim as string x

		while( i <= n )

			'' find end of line
			i = i0
			while( i <= n )
				select case sBody[i]
				case 10, 13
					exit while
				end select
				i += 1
			wend
			x = mid( sBody, i0 + 1, i - i0 )

			'' skip any LF and CR's
			while( i <= n )
				select case sBody[i]
				case 10, 13
					i += 1
				case else
					exit while
				end select
			wend
			i0 = i

			if( bFirstMark ) then
				if x = "----" then
					bFirstMark = FALSE
					exit while
				elseif( len(x) > 2 ) then
					'' find the page name
					for i = 1 to len(x)
						select case mid( x, i, 1 )
						case "A" to "Z", "a" to "z", "0" to "9", "_"
						case else
							exit for
						end select
					next
					if i > 1 then
						txt &= left(x, i - 1) & nl
					end if
				end if
			else
				if x = "----" then
					bFirstMark = TRUE
				end if
			end if

		wend
		
		sBody = txt

	end sub

	'':::::
	private function get_pageid _
		( _
			byval ctx as CWikiConUrlCtx ptr _
		) as integer

		dim as CHttpStream ptr stream

		function = -1

		stream = new CHttpStream( ctx->http )
		if( stream = NULL ) then
			exit function
		end if

		dim as string body, URL
		URL = build_url( ctx, NULL, wakka_getid )

		if( stream->Receive( URL, TRUE, ctx->ca_file ) ) then
			body = stream->Read()
		end if

		delete stream

		if( check_iserror( body ) = FALSE ) then
			remove_http_headers( body )
			function = valint( get_response( body ) )
		end if
		
	end function

	'':::::
	function CWikiConUrl.LoadPage _
		( _
			byval pagename as zstring ptr, _
			byref body as string _
		) as boolean

		function = FALSE
		body = ""

		if( ctx = NULL ) then
			exit function
		end if

		ZSet @ctx->pagename, pagename
		ctx->pageid = -1

		dim as CHttpStream ptr stream

		stream = new CHttpStream( ctx->http )
		if( stream = NULL ) then
			exit function
		end if

		dim URL as string
		URL = build_url( ctx, NULL, @wakka_raw )

		if( stream->Receive( URL, TRUE, ctx->ca_file ) ) then
			body = stream->Read()
			remove_http_headers( body )
		end if

		delete stream

		ctx->pageid = get_pageid( ctx )

		function = cbool( ctx->pageid > 0 )

	end function

	'':::::
	function CWikiConUrl.LoadIndex _
		( _
			byval page as zstring ptr, _
			byref body as string, _
			byval format as CWikiCon.IndexFormat _
		) as boolean

		dim isHTML as boolean = false

		function = FALSE
		body = ""
		
		if( ctx = NULL ) then
			exit function
		end if

		ZSet @ctx->pagename, page
		ctx->pageid = -1
		
		dim as CHttpStream ptr stream
		
		stream = new CHttpStream( ctx->http )
		if( stream = NULL ) then
			exit function
		end if

		dim URL as string

		select case format
		case CWikiCon.IndexFormat.INDEX_FORMAT_LEGACY
			'' cheap trick to use the rawlist format for PageIndex and RecentChanges"
			if( *page = "PageIndex" ) then
				URL = build_url( ctx, NULL, wakka_rawlist )
			elseif( *page = "RecentChanges" ) then
				URL = build_url( ctx, NULL, wakka_rawlist_index )
			else
				URL = build_url( ctx, NULL, NULL )
				isHTML = true
			end if

		case CWikiCon.IndexFormat.INDEX_FORMAT_HTML
			URL = build_url( ctx, NULL, NULL )
			isHTML = true

		case CWikiCon.IndexFormat.INDEX_FORMAT_LIST
			URL = build_url( ctx, NULL, wakka_rawlist )

		case CWikiCon.IndexFormat.INDEX_FORMAT_INDEX
			URL = build_url( ctx, NULL, wakka_rawlist_index )

		case else
			delete stream
			exit function

		end select

		if( stream->Receive( URL, TRUE, ctx->ca_file ) ) then
			body = stream->Read()
			remove_http_headers( body )
			if( isHTML ) then
				remove_html_tags(  body )
				extract_page_names( body )
			end if
			function = TRUE
		end if

		delete stream

		ctx->pageid = -1

	end function

	'':::::
	function CWikiConUrl.StorePage _
		( _
			byval body as zstring ptr, _
			byval note as zstring ptr _
		) as boolean
		
		dim body_out as string

		if( ctx = NULL ) then
			return FALSE
		end if

		if( ctx->queryCsrfToken( ) = FALSE ) then
			return FALSE
		end if

		if( ctx->pageid <= 0 ) then
			return FALSE
		end if

		dim as CHttpForm ptr form

		form = new CHttpForm
		if( form = NULL ) then
			return FALSE
		end if

		form->Add( "wakka", *ctx->pagename + wakka_edit )
		form->Add( "previous",  ctx->pageid )
		body_out = *body

		form->Add( "body", body_out, "text/html" )
		if( note ) then
			form->Add( "note", *note )
		else
			form->Add( "note", "updated" )
		end if
		form->Add( "submit", "Store" )
		ctx->maybeAddCsrfTokenToForm( form )

		dim url as string 
		URL = build_url( ctx, NULL, wakka_edit )

		dim as string response = ctx->http->Post( url, form, ctx->ca_file )

		dim as integer res = ( check_iserror( response ) = FALSE )

		if( res ) then 
			ctx->pageid = get_pageid( ctx )
		end if

		delete form

		function = res

	end function

	'':::::
	function CWikiConUrl.StoreNewPage _
		( _
			byval body as zstring ptr, _
			byval pagename as zstring ptr _
		) as boolean

		if( ctx = NULL ) then
			return FALSE
		end if

		if( ctx->queryCsrfToken( ) = FALSE ) then
			return FALSE
		end if

		dim as CHttpForm ptr form

		form = new CHttpForm
		if( form = NULL ) then
			return FALSE
		end if

		form->Add( "wakka", *pagename + wakka_edit )
		form->Add( "previous",  " " )
		form->Add( "body", body, "text/html" )
		form->Add( "note", "new page" )
		form->Add( "submit", "Store" )
		ctx->maybeAddCsrfTokenToForm( form )

		dim URL as string
		URL = build_url( ctx, pagename, wakka_edit )

		dim as string response = ctx->http->Post( URL, form, ctx->ca_file )

		dim as integer res = ( check_iserror( response ) = FALSE )

		if( res ) then 
			ctx->pageid = get_pageid( ctx )
		end if

		delete form

		function = res

	end function

	'':::::
	function CWikiConUrl.GetPageID _
		( _
		) as integer

		if( ctx = NULL ) then
			return 0
		end if

		return ctx->pageid

	end function

end namespace
