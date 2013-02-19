%%%===================================================================
%%% The Erlangville Cycle Hire System
%%% Simon Kers -- KTH 2013
%%%===================================================================
-module(ev_supervisor).
-author('skers@kth.se').

-behaviour(supervisor).

%% API
-export([start_link/0,
         start_child/2]).

%% Supervisor callbacks
-export([init/1]).

-record(state, {ref, pid, total, occupied}).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    {ok, Pid} = supervisor:start_link({local, ?MODULE}, ?MODULE, []),
    {ok, Pid}.

start_child(Total, Occupied) ->
    %% create a unique reference for the station
    StationRef = make_ref(),
    Args = [StationRef, Total, Occupied],
    {ok, _Pid} = supervisor:start_child(?MODULE, Args),
    {ok, StationRef}.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init(Args) ->
    ets:new(ev_db, [set, public, named_table, {keypos, #state.ref}]),
    Restart = {simple_one_for_one, 5, 60},
    ChildSpec = {station,
                 {ev_docking_station, start_link, Args},
                 permanent, 5000, worker,
                 [ev_docking_station]},
    {ok, {Restart, [ChildSpec]}}.

