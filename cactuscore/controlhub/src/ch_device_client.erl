%%% ===========================================================================
%%% @author Robert Frazier
%%%
%%% @since May 2012
%%%
%%% @doc A device client forms a single point of contact with a particular
%%%      hardware target, and deals with all the UDP communication to that
%%%      particular target.  The interface simply allows you to queue
%%%      transactions for a particular target, with the relevant device client
%%%      being found (or spawned) behind the scenes.  Replies from the target
%%%      device are sent back as a message to the originating process.
%%% @end
%%% ===========================================================================
-module(ch_device_client).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include("ch_global.hrl").
-include("ch_timeouts.hrl").
-include("ch_error_codes.hrl").

%% --------------------------------------------------------------------
%% External exports
-export([start_link/2, enqueue_requests/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3,
         reset_packet_id/2, parse_packet_header/1]).

-record(state, {socket, nextpktid}).           % Holds network socket to target device.


%%% ====================================================================
%%% API functions (public interface)
%%% ====================================================================


%% ---------------------------------------------------------------------
%% @doc Start up a Device Client for a given target IP address (given
%%      as a 32-bit uint) and port number (16-bit uint).
%%
%% @spec start_link(IPaddrU32::integer(), PortU16::integer()) -> {ok, Pid} | {error, Error}
%% @end
%% ---------------------------------------------------------------------
start_link(IPaddrU32, PortU16) when is_integer(IPaddrU32), is_integer(PortU16) ->
    gen_server:start_link(?MODULE, [IPaddrU32, PortU16], []).


%% ---------------------------------------------------------------------
%% @doc Add some IPbus requests to the queue of the device client  
%%      dealing with the target hardware at the given IPaddr and Port.
%%      Note that the IP address is given as a raw unsigned 32-bit
%%      integer (no "192.168.0.1" strings, etc). Once the device client
%%      has dispatched the requests, the received responses will be
%%      forwarded to the caller of this function using the form:
%%
%%        { device_client_response,
%%          TargetIPaddrU32::integer(),
%%          TargetPortU16::integer(),
%%          ErrorCodeU16::integer(),
%%          TargetResponse::binary() }
%%
%%      Currently ErrorCodeU16 will either be:
%%          0  :  Success, no error.
%%          1  :  Target response timeout reached.
%%
%%      If the the error code is not 0, then the TargetResponse will be
%%      an empty binary. 
%%
%% @spec enqueue_requests(IPaddrU32::integer(),
%%                        PortU16::integer(),
%%                        IPbusRequests::binary()) -> ok
%% @end
%% ---------------------------------------------------------------------
enqueue_requests(IPaddrU32, PortU16, IPbusRequests) when is_binary(IPbusRequests) ->
    {ok, Pid} = ch_device_client_registry:get_pid(IPaddrU32, PortU16),
    gen_server:cast(Pid, {send, IPbusRequests, self()}),
    ok.
    
    

%%% ====================================================================
%%% Behavioural functions: gen_server callbacks
%%% ====================================================================


%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
init([IPaddrU32, PortU16]) ->
    % Put process constants in process dict.
    put(target_ip_u32, IPaddrU32),
    put(target_ip_tuple, ch_utils:ipv4_u32_addr_to_tuple(IPaddrU32)),
    put(target_port, PortU16),
    
    % Try opening ephemeral port and we want data delivered as a binary.
    case gen_udp:open(0, [binary]) of   
        {ok, Socket} ->
            put(socket, Socket),
            {ok, #state{socket = Socket}};
        {error, Reason} when is_atom(Reason) ->
            ErrorMessage = {"Device client couldn't open UDP port to target",
                            get(targetSummary),
                            {errorCode, Reason}
                           },
            {stop, ErrorMessage};
        _ ->
            ErrorMessage = {"Device client couldn't open UDP port to target",
                            get(targetSummary),
                            {errorCode, unknown}
                           },
            {stop, ErrorMessage}
    end.
    
    

%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.


%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------

% handle_cast callback for enqueue_requests API call.
handle_cast({send, RawIPbusRequest, ClientPid}, State = #state{socket = Socket}) ->
    ?DEBUG_TRACE("IPbus request packet received from Transaction Manager with PID = ~w.  Forwarding to "
                 "IP addr=~w, port=~w...", [ClientPid, get(target_ip_tuple), get(target_port)]),
    ?PACKET_TRACE(RawIPbusRequest, "The following IPbus request have been received from Transaction " 
                  "Manager with PID = ~w.  Forwarding to IP addr=~w, port=~w...",
                  [ClientPid, get(target_ip_tuple), get(target_port)]),
    try reset_packet_id(RawIPbusRequest, State#state.nextpktid) of 
        {ModRequest, PktId} -> 
            TargetIPTuple = get(target_ip_tuple),
            TargetPort = get(target_port),
            gen_udp:send(Socket, TargetIPTuple, TargetPort, ModRequest),
            ch_stats:udp_out(),
            Reply = receive
                        {udp, Socket, TargetIPTuple, TargetPort, HardwareReplyBin} -> 
                            ?DEBUG_TRACE("Received response from target hardware at IP addr=~w, port=~w. "
                                         "Passing it to originating Transaction Manager...", [TargetIPTuple, TargetPort]),
                            ch_stats:udp_in(),
                            { device_client_response, get(target_ip_u32), TargetPort, ?ERRCODE_SUCCESS, HardwareReplyBin}
                    after ?UDP_RESPONSE_TIMEOUT ->
                        ?DEBUG_TRACE("TIMEOUT REACHED! No response from target (IPaddr=~w, port=~w) . Generating and sending "
                                     "a timeout response to originating Transaction Manager...", [TargetIPtuple, TargetPort]),
                        ch_stats:udp_response_timeout(),
                        { device_client_response, get(target_ip_u32), TargetPort, ?ERRCODE_TARGET_CONTROL_TIMEOUT, <<>> }
                    end,
            ClientPid ! Reply,
            if 
              (is_integer(PktId) and PktId =< 16#ffff) -> 
                {noreply, State#state{nextpktid = PktId + 1}};
              is_integer(PktId) ->
                {noreply, State#state{nextpktid = 1}};
              true -> 
              {noreply, State}
            end
    catch
        throw: malformed ->
            ClientPid ! { device_client_response, get(target_ip_u32), get(target_port), ?ERRCODE_MALFORMED_STATUS, <<>> },
            {noreply, State};
        throw: {timeout, status, _Details} ->
            ClientPid ! { device_client_response, get(target_ip_u32), get(target_port), ?ERRCODE_TARGET_STATUS_TIMEOUT, <<>> },
            {noreply, State};
        throw: {timeout, resent, _Details} ->
            ClientPid ! { device_client_response, get(target_ip_u32), get(target_port), ?ERRCODE_TARGET_RESEND_TIMEOUT, <<>> },
            {noreply, State}
    end;

%% Default handle cast
handle_cast(_Msg, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%% --------------------------------------------------------------------
%%% Internal functions (private)
%%% --------------------------------------------------------------------


%% ---------------------------------------------------------------------
%% @doc 
%% @throws Same as get_device_status/0
%% @spec reset_packet_id(RawIPbusRequestBin, Id) -> (ModIPbusRequest, PacketId}
%% ---------------------------------------------------------------------

reset_packet_id(RawIPbusRequest, NewId) ->
    {MajorVer, _MinorVer, _, End} = parse_packet_header(RawIPbusRequest),
    case {MajorVer, NewId} of
        {2, _} when is_integer(NewId) ->
             <<H1:8, _:16, H2:8, PktBody/binary>> = RawIPbusRequest,
             case End of
                 big    -> {<<H1:8, NewId:16/big, H2:8, PktBody/binary>>, NewId};
                 little -> {<<H1:8, NewId:16/little, H2:8, PktBody/binary>>, NewId}
             end;
        {2, _} ->
             {_, IdFromStatus} = get_device_status(),
             reset_packet_id(RawIPbusRequest, IdFromStatus);
        {_, _} ->
             {RawIPbusRequest, notset}
    end.


%% ---------------------------------------------------------------------
%% @doc
%% @spec
%% ---------------------------------------------------------------------

% {MajorVer, _MinorVer, Id, End} = parse_packet_header(RawHeader),
parse_packet_header(PacketBin) when size(PacketBin)>4 ->
    <<Header:4/binary, _/binary>> = PacketBin,
    parse_packet_header(Header);
parse_packet_header(<<16#20:8/big, Id:16/big, 16#f0:8/big>>) ->
    {2, 0, Id, big};
parse_packet_header(<<16#f0:8/big, Id:16/little, 16#20:8/big>>) ->
    {2, 0, Id, little};
parse_packet_header(_) ->
    {1, unknown, notset, unknown}.


%% ---------------------------------------------------------------------
%% @doc
%% @throws malformed , plus same as service_port_send_reply/2
%% @spec get_device_status() -> {NrResponseBuffers, NextExpdId}
%% ---------------------------------------------------------------------

get_device_status() ->
    case service_port_send_reply(control, 2) of 
        {ok, << 16#200000ff:32,_Word1:4/binary, NrBuffers:32,
               _:8, NextId:16, _:8, _TheRest/binary >>} ->
            {NrBuffers, NextId};
        {ok, _Response} ->
             ?DEBUG_TRACE("Malformed status response received from target at IP addr=~w, status port=~w. Will now throw the atom 'malformed'"
                          [get(target_ip_tuple), get(target_port)+1]),
             ?PACKET_TRACE(_Response, "The following malformed status response has been received from target at IP addr=~w, status port=~w."
                                      [get(target_ip_tuple), get(target_port)+1]),
             throw(malformed)
    end.


%% ---------------------------------------------------------------------
%% @doc  
%% @throws {timeout, PortAtom, Details}
%% @spec service_port_send_reply(PortAtom, MaxNrSends) -> {ok, ResponseBin}
%%       where
%%         PortAtom = status | reply
%%       end
%% ---------------------------------------------------------------------

service_port_send_reply(status, MaxNrSends) -> 
    Word = 16#200000f0,
    RequestBin = << Word:32, Word:32, Word:32, Word:32,
                    Word:32, Word:32, Word:32, Word:32,
                    Word:32, Word:32, Word:32, Word:32,
                    Word:32, Word:32, Word:32, Word:32 >>,
    try sync_send_reply(RequestBin, get(target_port)+1, get(target_port)+1, MaxNrSends, ?UDP_RESPONSE_TIMEOUT) of 
        X -> X
    catch
        throw:{timeout, Details} ->
            throw({timeout, status, Details})
    end;

service_port_send_reply(resend, MaxNrSends) ->
    try sync_send_reply(<<0:32>>, get(target_port)+2, get(target_port), MaxNrSends, ?UDP_RESPONSE_TIMEOUT) of
        X -> X
    catch
        throw:{timeout, Details} ->
            throw({timeout, resend, Details})
    end.


%% ----------------------------------------------------------------------
%% @doc Sends packet to device, waits for reply, and if timeout occurs, 
%%      retries specified number of times 
%% @throws {timeout, Details}
%% @spec sync_send_reply(RequestBin, SendPort, ReplyPort, MaxNrSends, TimeoutEachSend) -> {ok, ResponseBin}
%% ----------------------------------------------------------------------

sync_send_reply(BinToSend, SendPort, ReplyPort, MaxNrSends, TimeoutEachSend) ->
    sync_send_reply(BinToSend, SendPort, ReplyPort, MaxNrSends, TimeoutEachSend, 0).


%% ----------------------------------------------------------------------
%% @doc
%% @spec
%% ----------------------------------------------------------------------

sync_send_reply(_BinToSend, SendPort, ReplyPort, MaxNrSends, TimeoutEachSend, MaxNrSends) ->
    TargetIPTuple = get(target_ip_tuple),
    ?DEBUG_TRACE("MAX NUMBER OF TIMEOUTS in sync_send_reply/6! No response from target (IPaddr=~w, send to port=~w, reply port=~w) after ~w attempts, each with timeout of ~wms"
                 "Throwing now", [TargetIPTuple, SendPort, ReplyPort, MaxNrSends, TimeoutEachSend]),
    throw({timeout, io:lib_format("Communicating with board at ~w (send to port ~w, reply port ~w). No response after ~w attempts, each with timeout of ~wms.", [TargetIPTuple, SendPort, ReplyPort, MaxNrSends, TimeoutEachSend])});

sync_send_reply(BinToSend, SendPort, ReplyPort, MaxNrSends, TimeoutEachSend, SendCount) ->
    Socket = get(socket),
    TargetIPTuple = get(target_ip_tuple),
    gen_udp:send(Socket, TargetIPTuple, SendPort, BinToSend),
    ch_stats:udp_out(),
    receive
        {udp, Socket, TargetIPTuple, ReplyPort, ReplyBin} -> 
            ?DEBUG_TRACE("In sync_send_reply/6 : Received response from target hardware at IP addr=~w, send port=~w, reply port=~w on attempt no. ~w of ~w", 
                         [TargetIPTuple, SendPort, ReplyPort, SendCount+1, MaxNrSends]),
            ch_stats:udp_in(),
            {ok, ReplyBin}
    after TimeoutEachSend ->
        ?DEBUG_TRACE("TIMEOUT REACHED in sync_send_reply/6! No response from target (IPaddr=~w, send port=~w, reply port=~w) on attempt no. ~w of ~w."
                     " I might try again ...", [TargetIPTuple, SendPort, ReplyPort, SendCount+1, MaxNrSends]),
        ch_stats:udp_response_timeout(),
        sync_send_reply(BinToSend, SendPort, ReplyPort, MaxNrSends, TimeoutEachSend, SendCount+1)
    end.


