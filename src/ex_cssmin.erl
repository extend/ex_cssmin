%% @author Loïc Hoguin <essen@dev-extend.eu>
%% @copyright 2011 Loïc Hoguin.
%%
%% Based on the YUI Compressor's CSS minifier by Julien Lecomte,
%% itself adapted from Isaac Schlueter's cssmin utility.
%%
%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions are met:
%%
%%   * Redistributions of source code must retain the above copyright notice,
%%     this list of conditions and the following disclaimer.
%%   * Redistributions in binary form must reproduce the above copyright notice,
%%     this list of conditions and the following disclaimer in the documentation
%%     and/or other materials provided with the distribution.
%%   * Neither the name of this project nor the names of its contributors may be
%%     used to endorse or promote products derived from this software without
%%     specific prior written permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
%% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
%% FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
%% DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
%% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
%% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
%% OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

-module(ex_cssmin).
-export([minify/1]).

%% @doc CSS minifier.
%% @spec minify(CSS) -> CSS
%%       CSS = [binary()]
minify(CSS) ->
	ReOpts = [global],
	%% Remove all comment blocks.
	CSS2 = re:replace(CSS, "\\/\\*[^*]*\\*+([^/][^*]*\\*+)*\\/", ""),
	%% Normalize all whitespace strings to single spaces. Easier to work with that way.
	CSS3 = re:replace(CSS2, "\\s+", " ", ReOpts),
	%% Remove the spaces before the things that should not have spaces before them.
	%% But, be careful not to turn "p :link {...}" into "p:link{...}".
	%% Swap out any pseudo-class colons with the token, and then swap back.
	CSS4 = remove_ws_before(CSS3, ReOpts),
	%% Remove the spaces after the things that should not have spaces after them.
	CSS5 = re:replace(CSS4, "([!{}:;>+\\(\\[,])\\s+", "\\1", ReOpts),
	%% Add the semicolon where it's missing.
	CSS6 = re:replace(CSS5, "([^;\\}])}", "\\1;}", ReOpts),
	%% Replace 0(px,em,%) with 0.
	CSS7 = re:replace(CSS6, "([\\s:])(0)(px|em|%|in|cm|mm|pc|pt|ex)", "\\1\\2", ReOpts),
	%% Replace 0 0 0 0; with 0.
	%% Be careful not to mess up background-position though.
	CSS8 = re:replace(CSS7, ":0 0 0 0;", ":0;", ReOpts),
	CSS9 = re:replace(CSS8, ":0 0 0;", ":0;", ReOpts),
	CSS10 = re:replace(CSS9, ":0 0;", ":0;", ReOpts),
	CSS11 = re:replace(CSS10, "background-position:0;", "background-position:0 0;", ReOpts),
	%% Replace 0.6 to .6, but only when preceded by : or a white-space.
	CSS12 = re:replace(CSS11, "(:|\\s)0+\\.(\\d+)", "\\1.\\2", ReOpts),
	%% Shorten colors from rgb(51,102,153) to #336699.
	%% This makes it more likely that it'll get further compressed in the next step.
	CSS13 = shorten_colors_rgb_func(CSS12),
	%% Shorten colors from #AABBCC to #ABC. Note that we want to make sure
	%% the color is not preceded by either ", " or =. Indeed, the property
	%%     filter: chroma(color="#FFFFFF");
	%% would become
	%%     filter: chroma(color="#FFF");
	%% which makes the filter break in IE.
	CSS14 = shorten_colors_rgb(CSS13),
	%% Remove empty rules.
	CSS15 = re:replace(CSS14, "[^\\}]+\\{;\\}", "", ReOpts),
	%% Replace multiple semi-colons in a row by a single one.
	CSS16 = re:replace(CSS15, ";;+", ";", ReOpts),
	%% Remove the last semi-colon of properties.
	CSS17 = re:replace(CSS16, ";}", "}", ReOpts),
	%% Trim the final string (for any leading or trailing white spaces),
	%% add a line break at the very end, and return as a binary.
	iolist_to_binary(re:replace(CSS17, "^\\s*(.+)\\s*$", "\\1\n", ReOpts)).

remove_ws_before(CSS, ReOpts) ->
	{ok, MP} = re:compile("(^|\\})(([^\\{:])+:)+([^\\{]*\\{)"),
	CSS2 = remove_ws_before(iolist_to_binary(CSS), MP, re:run(CSS, MP, [{capture, first}]), []),
	CSS3 = re:replace(CSS2, "\\s+([!{};:>+\\(\\)\\],])", "\\1", ReOpts),
	re:replace(CSS3, "___PSEUDOCLASSCOLON___", ":", ReOpts).
remove_ws_before(CSS, _MP, nomatch, Acc) ->
	iolist_to_binary(lists:reverse([CSS|Acc]));
remove_ws_before(CSS, MP, {match, [{Offset, Length}]}, Acc) ->
	BeforeBits = Offset * 8,
	MatchBits = (Length - 1) * 8,
	<< BeforeBin:BeforeBits/bits, MatchBin:MatchBits/bits, Rest/bits >> = CSS,
	MatchBin2 = iolist_to_binary(re:replace(MatchBin, ":", "___PSEUDOCLASSCOLON___")),
	Bin = << BeforeBin/binary, MatchBin2/binary >>,
	remove_ws_before(Rest, MP, re:run(Rest, MP, [{capture, first}]), [Bin|Acc]).

shorten_colors_rgb_func(CSS) ->
	{ok, MP} = re:compile("rgb\\s*\\(\\s*([0-9,\\s]+)\\s*\\)"),
	shorten_colors_rgb_func(iolist_to_binary(CSS), MP, re:run(CSS, MP), []).
shorten_colors_rgb_func(CSS, _MP, nomatch, Acc) ->
	iolist_to_binary(lists:reverse([CSS|Acc]));
shorten_colors_rgb_func(CSS, MP, {match, [{Offset, Length}, {ArgsOffset, ArgsLength}]}, Acc) ->
	BeforeBits = Offset * 8,
	MatchBits = Length * 8,
	<< BeforeBin:BeforeBits/bits, MatchBin:MatchBits/bits, Rest/bits >> = CSS,
	ArgsBeforeBits = (ArgsOffset - Offset) * 8,
	ArgsMatchBits = ArgsLength * 8,
	<< _:ArgsBeforeBits/bits, ArgsBin:ArgsMatchBits/bits, _/bits >> = MatchBin,
	[RL, GL, BL] = re:split(ArgsBin, ",", [{return,list}]),
	[R, G, B] = [list_to_integer(RL), list_to_integer(GL), list_to_integer(BL)],
	RGBList = [integer_to_hex(R), integer_to_hex(G), integer_to_hex(B)],
	RGBBin = iolist_to_binary(RGBList),
	Bin = << BeforeBin/binary, $#, RGBBin/binary >>,
	shorten_colors_rgb_func(Rest, MP, re:run(Rest, MP), [Bin|Acc]).

integer_to_hex(N) when N < 256 ->
	[hex(N div 16), hex(N rem 16)].

hex(N) when N < 10 ->
	$0 + N;
hex(N) when N >= 10, N < 16 ->
	$a + (N - 10).

shorten_colors_rgb(CSS) ->
	{ok, MP} = re:compile("([^\"'=\\s])(\\s*)#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])"),
	shorten_colors_rgb(iolist_to_binary(CSS), MP, re:run(CSS, MP), []).
shorten_colors_rgb(CSS, _MP, nomatch, Acc) ->
	iolist_to_binary(lists:reverse([CSS|Acc]));
shorten_colors_rgb(CSS, MP, {match, MatchOffsets}, Acc) ->
	[_All, _First, _Second, {Offset, _One}|_Tail] = MatchOffsets,
	BeforeBits = Offset * 8,
	<< BeforeBin:BeforeBits/bits, MatchBin:48/bits, Rest/bits >> = CSS,
	MatchBin2 = lowercase_color(MatchBin),
	MatchBin3 = case MatchBin2 of
		<< A:8, A:8, B:8, B:8, C:8, C:8 >> -> << A:8, B:8, C:8 >>;
		_Any -> MatchBin2
	end,
	Bin = << BeforeBin/binary, MatchBin3/binary >>,
	shorten_colors_rgb(Rest, MP, re:run(Rest, MP), [Bin|Acc]).

lowercase_color(Hex) ->
	Hex2 = re:replace(Hex,  "A", "a", [global]),
	Hex3 = re:replace(Hex2, "B", "b", [global]),
	Hex4 = re:replace(Hex3, "C", "c", [global]),
	Hex5 = re:replace(Hex4, "D", "d", [global]),
	Hex6 = re:replace(Hex5, "E", "e", [global]),
	Hex7 = re:replace(Hex6, "F", "f", [global]),
	iolist_to_binary(Hex7).
