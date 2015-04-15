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

-module(project_handler).
-behaviour(cowboy_http_handler).
-author('flygoast@126.com').


-export([init/3,
         handle/2,
         terminate/3]).


-include("tbcd.hrl").


-record(state, {}).


init(_, Req, _Opts) ->
	{ok, Req, #state{}}.


handle(Req, State=#state{}) ->
    {ok, Body, Req2} = cowboy_req:body(Req),

    lager:info("body: ~p", [Body]),

    case catch jiffy:decode(Body) of
    {Ls} ->
        case lists:keyfind(<<"mode">>, 1, Ls) of
        false ->
            lager:info("mode argument not supplied", []),
            Content = jiffy:encode({[{<<"code">>, 1},
                                     {<<"reason">>,
                                      <<"mode argument not supplied">>}
                                    ]}),
            tbcd_reply:reply_json(Req2, State, 200, Content);
        {_, <<"add">>} ->
            case project_add(Ls) of
            {aborted, _Reason} ->
                tbcd_reply:reply_plain(Req2, State, 500,
                                       <<"Internal server error">>);
            {error, Reason} ->
                Content = jiffy:encode({[{<<"code">>, 1},
                                         {<<"reason">>,
                                          list_to_binary(Reason)}
                                        ]}),
                tbcd_reply:reply_json(Req2, State, 200, Content);
            ok ->
                Content = jiffy:encode({[{<<"code">>, 0}]}),
                tbcd_reply:reply_json(Req2, State, 200, Content)
            end;
        {_, <<"delete">>} ->
            case project_delete(Ls) of
            {aborted, _Reason} ->
                tbcd_reply:reply_plain(Req2, State, 500,
                                       <<"Internal server error">>);
            {error, Reason} ->
                Content = jiffy:encode({[{<<"code">>, 1},
                                         {<<"reason">>,
                                          list_to_binary(Reason)}]}),
                tbcd_reply:reply_json(Req2, State, 200, Content);
            ok ->
                Content = jiffy:encode({[{<<"code">>, 0}]}),
                tbcd_reply:reply_json(Req2, State, 200, Content)
            end;
        {_, <<"select">>} ->
            case lists:keyfind(<<"project">>, 1, Ls) of
            false ->
                Projects = project_select(),
                lager:info("get all projects: ~p", [Projects]),
                Content = jiffy:encode({[{<<"code">>, 0},
                                         {<<"projects">>, Projects}]}),
                tbcd_reply:reply_json(Req2, State, 200, Content);
            {_, P} ->
                case project_select(P) of
                {aborted, _Reason} ->
                    tbcd_reply:reply_plain(Req2, State, 500,
                                           <<"Internal server error">>);
                {error, Reason} ->
                    Content = jiffy:encode({[{<<"code">>, 1},
                                             {<<"reason">>,
                                              list_to_binary(Reason)}]}),
                    tbcd_reply:reply_json(Req2, State, 200, Content);
                Rs ->
                    Content = jiffy:encode({[{<<"code">>, 0},
                                             {<<"workers">>, Rs}]}),
                    tbcd_reply:reply_json(Req2, State, 200, Content)
                end
            end;
        {_, Mode} ->
            lager:error("invalid mode argument: ~p", [Mode]),
            Content = jiffy:encode({[{<<"code">>, 1},
                                     {<<"reason">>,
                                      <<"invalid mode argument">>}]}),
            tbcd_reply:reply_json(Req2, State, 200, Content)
        end;
    {error, Reason} ->
        lager:info("invalid json: ~p", [Reason]),
        Content = jiffy:encode({[{<<"code">>, 1},
                                 {<<"reason">>, <<"invalid json">>}]}),
        tbcd_reply:reply_json(Req2, State, 200, Content)
    end.


terminate(_Reason, _Req, _State) ->
	ok.


project_select() ->
    mnesia:dirty_all_keys(project).


project_select(P) ->
    F = fun() ->
            case mnesia:read(project, P) of
            [] ->
                lager:info("select: project ~p not existed", [P]),
                {error, "project not existed"};
            [#project{workers = W}] ->
                Workers = sets:to_list(W),
                lager:info("select: project: ~p, workers: ~p", [P, Workers]),
                Workers
            end
        end,

    case mnesia:transaction(F) of
    {atomic, Rs} ->
        Rs;
    {aborted, Reason} ->
        lager:error("select: mnesia error: ~p", [Reason]),
        {aborted, Reason}
    end.


project_delete(Ls) ->
    Workers = case lists:keyfind(<<"workers">>, 1, Ls) of
              false ->
                  [];
              {_, W} ->
                  W
              end,
    WkSet = sets:from_list(Workers),

    case lists:keyfind(<<"project">>, 1, Ls) of
    false ->
        {error, "project argument not supplied"};
    {_, P} ->
        F = fun() ->
                case mnesia:read(project, P) of
                [] ->
                    lager:info("delete: ~p not existed", [P]),
                    {error, "project not existed"};
                [#project{workers = OW}] ->
                    case Workers of
                    [] -> %% delete the project
                        lager:info("delete entile project: ~p", [P]),
                        mnesia:delete({project, P}),
                        ok;
                    _ -> %% delete the workers from project
                        NewWorkers = sets:subtract(OW, WkSet),
                        UWK = sets:to_list(WkSet),
                        NWL = sets:to_list(NewWorkers),
                        mnesia:write(#project{name = P, workers = NewWorkers}),
                        lager:info("delete project: ~p, workers: ~p, "
                                   "left workers: ~p",
                                   [P, UWK, NWL]),
                        ok
                    end
                end
            end,

        case mnesia:transaction(F) of
        {atomic, Rs} ->
            Rs;
        {aborted, Reason} ->
            lager:error("delete: mnesia error: ~p", [Reason]),
            {aborted, Reason}
        end
    end.

project_add(Ls) ->
    Wk = case lists:keyfind(<<"workers">>, 1, Ls) of
         false ->
             [];
         {_, W} ->
             W
         end,

    %% drop the duplicated
    WkSet = sets:from_list(Wk),
    UWK = sets:to_list(WkSet),

    case lists:keyfind(<<"project">>, 1, Ls) of
    false ->
        {error, "project argument not supplied"};
    {_, <<"">>} ->
        {error, "project argument is emtpy"};
    {_, P} ->
        F = fun() ->
                case mnesia:read(project, P) of
                [] ->
                    mnesia:write(#project{name = P, workers = WkSet}),
                    lager:info("add new project: ~p, workers: ~p",
                               [P, UWK]),
                    ok;
                [#project{workers = OW}] ->
                    NewWorkers = sets:union(OW, WkSet),
                    mnesia:write(#project{name = P, workers = NewWorkers}),
                    lager:info("add old project: ~p, old workers: ~p, "
                               "added workers: ~p, all workers: ~p",
                               [P, sets:to_list(OW),
                                UWK, sets:to_list(NewWorkers)]),
                    ok
                end
            end,

        case mnesia:transaction(F) of
        {atomic, Rs} ->
            Rs;
        {aborted, Reason} ->
            lager:error("add workers: mnesia error: ~p", [Reason]),
            {aborted, Reason}
        end
    end.
