%%%
%%% Copyright (c) 2015, Gu Feng <flygoast@126.com>
%%%
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions
%%% are met:
%%% 1. Redistributions of source code must retain the above copyright
%%%    notice, this list of conditions and the following disclaimer.
%%% 2. Redistributions in binary form must reproduce the above copyright
%%%    notice, this list of conditions and the following disclaimer in the
%%%    documentation and/or other materials provided with the distribution.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
%%% ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%%% ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
%%% FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
%%% DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
%%% OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
%%% HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
%%% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
%%% OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
%%% SUCH DAMAGE.
%%%
-module(tbcd_subtask).
-author('flygoast@126.com').


-include("tbcd.hrl").


-export([init/0,
         get_proc/0,
         http_recv/1]).


-record(state, {}).


init() ->
    loop(#state{}).


loop(State) ->
    receive
    {new, Tid, Project} ->
        lager:info("project: ~p, tid: ~p", [Project, Tid]),
        F = fun() ->
                case mnesia:read(project, Project) of
                [] ->
                    {error, "project not existed"};
                [#project{workers = W}] ->
                    L = sets:to_list(W),

                    lager:info("project: ~p, workers: ~p", [Project, L]),

                    lists:foreach(fun(Ele) ->
                                      ST = #subtask{sid = {Tid, Ele},
                                                    timestamp = now()},
                                      mnesia:write(unfetched_subtask, ST,
                                                   write),

                                      case global:whereis_name(Ele) of
                                      undefined ->
                                          ok;
                                      Pid ->
                                          Pid ! {reply}
                                      end,

                                      lager:info("new: ~p: ~p", [Tid, Ele])
                                  end, L),
                    length(L)
                end
            end,
        case mnesia:transaction(F) of
        {atomic, {error, Reason}} ->
            lager:error("new subtask error: ~p", [Reason]);
        {atomic, N} ->
            lager:info("new subtask count: ~p", [N]),
            mnesia:dirty_update_counter(task_count, Tid, N);
        {aborted, Reason} ->
            lager:error("mnesia error: ~p", [Reason])
        end,

        loop(State);
    {feedback, Tid, Incr} ->
        NewCount = mnesia:dirty_update_counter(task_count, Tid, Incr),

        lager:info("incr: ~p, feedback: ~p, count: ~p",
                   [Incr, Tid, NewCount]),

        case NewCount of
        0 ->
            F = fun() ->
                    case mnesia:read(task, Tid) of
                    [] ->
                        lager:error("feedback, invalid tid: ~p", [Tid]),
                        {error, "invalid tid"};
                    [#task{callback = undefined}] ->
                        ok;
                    [#task{callback = URL}] ->
                        %% get HTTP callback and all results
                        MatchHead = #subtask{sid = {Tid, '$1'},
                                             result = '$2', _ = '_'},
                        Guard = [],
                        Result = {[{<<"worker">>, '$1'}, {<<"result">>, '$2'}]},
                        R = mnesia:select(finished_subtask,
                                          [{MatchHead, Guard, [Result]}]),
                        {binary_to_list(URL), R}
                    end
                end,
            case mnesia:transaction(F) of
            {atomic, ok} ->
                ok;
            {atomic, {error, _Reason}} ->
                ok;
            {atomic, {Callback, Rs}} ->
                Content = jiffy:encode({[{<<"tid">>, Tid},
                                         {<<"results">>, Rs}]}),
                Headers = [{"Connection", "close"}],
                Req = {Callback, Headers, "application/json", Content},
                Opts = [{timeout, 10000}, {connect_timeout, 5000}],
                HttpOpts = [{sync, false}, {stream, self},
                            {receiver, {?MODULE, http_recv, []}}],
                {ok, RequestId} = httpc:request(post, Req, Opts, HttpOpts),

                lager:info("callback: ~p, tid: ~p, requestid: ~p",
                           [Callback, Tid, RequestId]);
            {aborted, Reason} ->
                lager:error("mnesia failed: ~p", [Reason])
            end;
        _ ->
            ok
        end,

        loop(State);
    stop ->
        ok;
    _ ->
        loop(State)
    end.


get_proc() ->
    list_to_atom(atom_to_list(node()) ++ "_" ++ "subtask").


http_recv({RequestId, {error, Reason}}) ->
    lager:error("http response error:[~p] ~p~n", [RequestId, Reason]),
    ok;
http_recv({RequestId, Result}) ->
    lager:info("http response result:[~p] ~p", [RequestId, Result]),
    ok;
http_recv({RequestId, stream_start, Headers}) ->
    lager:info("http response headers:[~p] ~p", [RequestId, Headers]),
    ok;
http_recv({RequestId, stream, BinBodyPart}) ->
    lager:info("http response body:[~p] ~p", [RequestId, BinBodyPart]),
    ok;
http_recv({RequestId, stream_end, _Headers}) ->
    lager:info("http response body end:[~p]", [RequestId]),
    ok.
