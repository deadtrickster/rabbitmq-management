%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ Management Console.
%%
%%   The Initial Developers of the Original Code are Rabbit Technologies Ltd.
%%
%%   Copyright (C) 2010 Rabbit Technologies Ltd.
%%
%%   All Rights Reserved.
%%
%%   Contributor(s): ______________________________________.
%%
-module(rabbit_mgmt_wm_queue).

-export([init/1, resource_exists/2, to_json/2,
         content_types_provided/2, content_types_accepted/2,
         is_authorized/2, allowed_methods/2, accept_content/2,
         delete_resource/2]).

-include("rabbit_mgmt.hrl").
-include_lib("webmachine/include/webmachine.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

%%--------------------------------------------------------------------
init(_Config) -> {ok, #context{}}.

content_types_provided(ReqData, Context) ->
   {[{"application/json", to_json}], ReqData, Context}.

content_types_accepted(ReqData, Context) ->
   {[{"application/json", accept_content}], ReqData, Context}.

allowed_methods(ReqData, Context) ->
    {['HEAD', 'GET', 'PUT', 'DELETE'], ReqData, Context}.

resource_exists(ReqData, Context) ->
    {case queue(ReqData) of
         not_found -> false;
         _         -> true
     end, ReqData, Context}.

to_json(ReqData, Context) ->
    Q0 = queue(ReqData),
    [Q] = rabbit_mgmt_db:get_queues([Q0]),
    rabbit_mgmt_util:reply(Q, ReqData, Context).

accept_content(ReqData, Context) ->
    Name = rabbit_mgmt_util:id(queue, ReqData),
    rabbit_mgmt_util:with_decode_vhost(
      [durable, auto_delete, arguments], ReqData, Context,
      fun(VHost, [Durable, AutoDelete, Arguments]) ->
              Durable1    = rabbit_mgmt_util:parse_bool(Durable),
              AutoDelete1 = rabbit_mgmt_util:parse_bool(AutoDelete),
              rabbit_mgmt_util:amqp_request(
                VHost, ReqData, Context,
                #'queue.declare'{ queue       = Name,
                                  durable     = Durable1,
                                  auto_delete = AutoDelete1,
                                  arguments   = [] }) %% TODO
      end).

delete_resource(ReqData, Context) ->
    try
        rabbit_mgmt_util:amqp_request(
          rabbit_mgmt_util:vhost(ReqData),
          ReqData, Context,
          #'queue.delete'{ queue = rabbit_mgmt_util:id(queue, ReqData) }),
        {true, ReqData, Context}
    catch {server_closed, Reason} ->
            rabbit_mgmt_util:bad_request(
              list_to_binary(Reason), ReqData, Context)
    end.

is_authorized(ReqData, Context) ->
    rabbit_mgmt_util:is_authorized(ReqData, Context).

%%--------------------------------------------------------------------

queue(ReqData) ->
    case rabbit_mgmt_util:vhost(ReqData) of
        none      -> not_found;
        not_found -> not_found;
        VHost     -> Name = rabbit_misc:r(VHost, queue,
                                          rabbit_mgmt_util:id(queue, ReqData)),
                     case rabbit_amqqueue:lookup(Name) of
                         {ok, X}            -> X;
                         {error, not_found} -> not_found
                     end
    end.