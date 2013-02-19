%%%===================================================================
%%% The Erlangville Cycle Hire System
%%% Simon Kers -- KTH 2013
%%%===================================================================
-module(ev_docking_station).
-author('skers@kth.se').

-behaviour(gen_fsm).

%% API
-export([start_link/2,
         start_link/3]).

%% gen_fsm callbacks
-export([init/1,
         state_name/2,
         handle_event/3,
         handle_sync_event/4,
         handle_info/3,
         terminate/3,
         code_change/4,
         idle/3,
         empty/3,
         full/3
        ]).
%% Client functions
-export([release_cycle/1,
         secure_cycle/1,
         get_info/1,
         update_db/2]).
%%Internal functions
-export([secure/1,
         release/1]).

%% State record
-record(state, {ref, pid, total, occupied}).

-define(DB, ev_db).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Total, Occupied) ->
    gen_fsm:start_link({global, ?MODULE}, ?MODULE, [Total, Occupied], []).

start_link(StationRef, Total, Occupied) ->
    gen_fsm:start_link(?MODULE, [StationRef, Total, Occupied], []).

release_cycle(Ref) ->
    [[Pid]] = ets:match(?DB, #state{ref=Ref,pid='$1',total='_',occupied='_'}),
    gen_fsm:sync_send_event(Pid, {release, Ref}).

secure_cycle(Ref) ->
    [[Pid]] = ets:match(?DB, #state{ref=Ref,pid='$1',total='_',occupied='_'}),
    gen_fsm:sync_send_event(Pid, {secure, Ref}).

get_info(Ref) ->
    [[Pid]] = ets:match(?DB, #state{ref=Ref,pid='$1',total='_',occupied='_'}),
    gen_fsm:sync_send_all_state_event(Pid, {info, Ref}).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm is started using gen_fsm:start/[3,4] or
%% gen_fsm:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @spec init(Args) -> {ok, StateName, State} |
%%                     {ok, StateName, State, Timeout} |
%%                     ignore |
%%                     {stop, StopReason}
%% @end
%%--------------------------------------------------------------------
init([_Ref, Total, _]) when Total < 1 ->
    {error, too_few};
init([Ref, _, _] = Args) ->
    update_db(?DB, Args),
    [State] = ets:lookup(?DB, Ref),
    Total = State#state.total,
    Occupied = State#state.occupied,

    case Total - Occupied of
        0     -> {ok, full, State};
        Total -> {ok, empty, State};
        _     -> {ok, idle, State}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec state_name(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
state_name(_Event, State) ->
    {next_state, state_name, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_event/[2,3], the instance of this function with
%% the same name as the current state name StateName is called to
%% handle the event.
%%
%% @spec state_name(Event, From, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {reply, Reply, NextStateName, NextState} |
%%                   {reply, Reply, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState} |
%%                   {stop, Reason, Reply, NewState}
%% @end
%%--------------------------------------------------------------------
idle({release, _Ref}, _From, State) ->
    NewState = release(State),
    ets:insert(?DB, NewState),

    case State#state.occupied of
        1 -> {reply, ok, empty, NewState};
        _ -> {reply, ok, idle, NewState}
    end;

idle({secure, _Ref}, _From, State) ->
    NewState = secure(State),
    ets:insert(?DB, NewState),

    case State#state.occupied == State#state.total of
        true  -> {reply, ok, full, NewState};
        false -> {reply, ok, idle, NewState}
    end.

empty({release, _Ref}, _From, State) ->
    Reply = {error, empty},
    {reply, Reply, empty, State};

empty({secure, _Ref}, _From, State) ->
    Reply = ok,
    {reply, Reply, idle, secure(State)}.

full({release, _Ref}, _From, State) ->
    Reply = ok,
    {reply, Reply, idle, release(State)};

full({secure, _Ref}, _From, State) ->
    Reply = {error, full},
    {reply, Reply, full, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @spec handle_event(Event, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_all_state_event/[2,3], this function is called
%% to handle the event.
%%
%% @spec handle_sync_event(Event, From, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {reply, Reply, NextStateName, NextState} |
%%                   {reply, Reply, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState} |
%%                   {stop, Reason, Reply, NewState}
%% @end
%%--------------------------------------------------------------------
handle_sync_event({info, _Ref}, _From, StateName, State) ->
    Free = State#state.total - State#state.occupied,
    Reply = [{total, State#state.total},
             {occupied, State#state.occupied},
             {free, Free}],
    {reply, Reply, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%%
%% @spec handle_info(Info,StateName,State)->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @spec terminate(Reason, StateName, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _StateName, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, StateName, State, Extra) ->
%%                   {ok, StateName, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

update_db(Db, [Ref, Total, Occupied]) ->
    Check = ets:match(ev_db, #state{ref=Ref,
                                    pid='_',
                                    total='$1',
                                    occupied='$2'}),
    io:format("~p~n", [Check]),
    case Check of
        [] -> % not in db
            ets:insert(Db, #state{ref = Ref,
                                  pid = self(),
                                  total = Total,
                                  occupied = Occupied});
        _InDb  ->
            [[OldTotal, OldOccupied]] = Check,
            ets:insert(Db, #state{ref = Ref,
                                  pid = self(),
                                  total = OldTotal,
                                  occupied = OldOccupied})
    end.

secure(State) ->
    {state,
     State#state.ref,
     State#state.pid,
     State#state.total,
     State#state.occupied + 1}.

release(State) ->
    {state,
     State#state.ref,
     State#state.pid,
     State#state.total,
     State#state.occupied - 1}.

