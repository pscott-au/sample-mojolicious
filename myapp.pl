#!/usr/bin/env perl
use Mojolicious::Lite;
use GraphQL::Type::Scalar qw($String);
use Mojo::Redis;
use DateTime;
use Mojo::JSON 'j';


helper redis => sub { state $r = Mojo::Redis->new($ENV{TEST_REDIS} || 'redis://localhost'); } ;

get '/' => sub {
  my $c = shift;
  $c->render(template => 'index');
};

get '/chat' => sub {
  my $c = shift;

  ## stash the GET param defined username/channel or set defaults
  $c->session->{'username'} =  $c->param('username') || 'Demo-name';
  $c->session->{'channel'}  =  $c->param('channel')  || 'Demo-channel';

  $c->render(template => 'chat'
  , 
    username => $c->session->{'username'},
    channel  => $c->session->{'channel'},
  
  );
};

## NB plugin not required to use chat however it does open up the GraphQL interface and allow alternative approach to sending messages and subscribing to PubSub
plugin GraphQL => {
  convert => [
    'MojoPubSub',
    { ## Redis Schema for Chat - also augmented with implicit  channel with pubsub and dateTime
      username => $String->non_null,
      message  => $String->non_null,
    },
    Mojo::Redis->new($ENV{TEST_REDIS} || 'redis://localhost'),
  ],
  graphiql => 1,
  keepalive => 5,
};


websocket '/socket' => sub {
    my $self = shift;
    $self->app->log->debug('Echo WebSocket opened');
    $self->inactivity_timeout(3000);
    my $pubsub = $self->redis->pubsub;

    my $name    = $self->session->{username}    || 'demo-username-none-in-session';
    my $channel = $self->session->{channel}     || 'Demo-channel';    

    my $cb = $pubsub->listen( $self->session->{'channel'} => sub  { 
        my ( $pubsub, $msg) = @_; 
        $self->send( $msg ); ## send message coming in from pubsub'd channel to user  through websocket
      });

    $self->on( message => sub { # Incoming websocket message
      my ($c, $msg) = @_;
      $pubsub->notify( $c->session->{'channel'} => j { message => $msg, username => $c->session->{'username'}, dateTime => DateTime->now->iso8601 } ); ## Send to Redis in same structure as GraphQL
      #$c->send({ json => { username => $c->session->{user}, message => $msg, dateTime => DateTime->now->iso8601 }}); ## also send to user through websocket
    });
    
    $self->on(finish => sub { # Closed websocket
      my ($c, $code, $reason) = @_;
      $c->app->log->debug("WebSocket closed with status $code");
    });
};



app->start;
__DATA__

@@ index.html.ep
% title 'Perl-GraphQL demo app';
<!DOCTYPE html>
<html lang="en">
<head>
  <title><%= title %></title>
</head>
<body>
<div id="page">
  <div id="content">
    <h1>Perl GraphQL Mojolicious Demo App</h1>
    <p>This demonstrates use of GraphQL in a Mojolicious::Lite app.</p>
    <p>The schema has one query field: <code>status</code>.</p>
    <p>The schema has one mutation field: <code>publish</code>.</p>
    <p>The schema has one subscription field: <code>subscribe</code>.</p>
    <p>The frontend uses the GraphiQL tool to query the Perl GraphQL backend.</p>
    <p>To use the demo, try these queries:</p>
    <p><code>
      query q {status}<br>
      mutation m {publish(input: { username: "u1", message: "m1", channel: "t1"})}<br>
      subscription s {subscribe(channels: ["t1"]) {channel username dateTime message}}
    </code></p>
    <p>in the left hand pane in GraphiQL, then run your query using the button at the top.</p>
    <p>Results are displayed in the pane to the right.</p>
    <h2>Click to <%= link_to 'enter GraphiQL' => '/graphql' %>.</h2>
  </div>
  <div id="chat-content">
  <h2>There is also a quick demonstration Chat App</h2>
  <ul>
    <a href="/chat?channel=starter&username=Larry">Open Channel 'starter' as User 'Larry'</a>
  </ul>
  </div>
<div>
</body>
</html>


@@ chat.html.ep
% title 'Perl-GraphQL demo Chat app';
<!DOCTYPE html>
<html lang="en">
<head>
  <title><%= title %></title>
<style>
/* From https://www.w3schools.com/howto/howto_css_chat.asp */
/* Chat message containers */
.chat-container {
  border: 2px solid #dedede;
  background-color: #f1f1f1;
  border-radius: 5px;
  padding: 10px;
  margin: 10px 0;
  position: relative;
}
/* Darker chat container */
.darker {
  border-color: #ccc;
  background-color: #ddd;
}
/* Clear floats */
.chat-container::after {
  content: "";
  clear: both;
  display: table;
}
/* Style images */
.chat-container img {
  float: left;
  max-width: 40px;
  width: 100%;
  margin-right: 20px;
  border-radius: 50%;
}
/* Style the right image */
.chat-container img.right {
  float: right;
  margin-left: 20px;
  margin-right:0;
}
.chat-container span.right {
  float: right;
}
/* Style time text */
.time-right {
  float: right;
  color: #aaa;
  font-size: small;
}
/* Style time text */
.time-left {
  float: left;
  color: #999;
  font-size: small;
}
/* ------- END CHAT STYLE ----- */
html, body {
  height: 100%;
  margin: 0;
  padding: 10px;
  font-family: 'Alatsi';font-size: 18px;
}
.row {
  display: flex;
}
.column {
  flex: 50%;
}
@media screen and (max-width: 600px) {
  .column {
    width: 100%;
  }
}
</style>
</head>
<body>
  <div id="page">
    <div id="content">
    <h1>Chat Demo '<%= $username %>' on channel '<%= $channel %>'</h1>
    <div class="row">
      <div class="column" style="background-color:#aaa;">
        <p>You can send a message through GraphQL with curl</p>
<code style="font-size: small;">
curl 'http://localhost:5000/graphql?' -H 'Accept: application/json' -H 'Content-Type: application/json' --data-binary '{"query":"mutation m {publish(input: { username: \"CLI-User\", message: \"Hello with curl through GraphQL\", channel: \"<%= $channel %>\"})}","operationName":"m"}'
</code>
      </div>    
      <div class="column" id='chat-panel' style="background-color:#bbb; overflow: auto; max-height: 400px"><!-- start col2 -->
      </div><!-- end col2 -->
    </div><!-- end row -->
    <div class="row">
      <div class="column"></div>
      <div class="column">
        <input type="text" id="chat-text" name="chat-text" size=40><button id='send-message' onClick="send_message()">Send Message</button>
      </div>
    </div>
    </div>
  </div>
<script>
var username = '<%= $username %>';
// WEBSOCKET
var ws = null;
if ("WebSocket" in window) {
  var loc = window.location, new_uri;
  if (loc.protocol === "https:") {
      new_uri = "wss:";
  } else {
      new_uri = "ws:";
  }
  new_uri += "//" + loc.host + "/socket";
  ws = new WebSocket( new_uri );
  ws.onmessage = function (event) { // add incoming message and scroll chat-panel to bottom
   var chatPanel = document.getElementById("chat-panel"); 
   try {
     var message_json = JSON.parse( event.data );
     if (message_json.message )
     {
      var locale = window.navigator.userLanguage || window.navigator.language;
      var local_time_string = new Date( message_json.dateTime + 'Z' ).toLocaleTimeString( locale,  { hour: 'numeric',minute: 'numeric'} );
       if ( message_json.username === username )
       { // Our message coming back through websocket
        chatPanel.innerHTML += '<div class="chat-container"><p>' +  message_json.message  + '</p><span class="time-right">' + local_time_string  + '</span></div>';
       }
       else 
       { // Someone elses message coming in through websocket
        chatPanel.innerHTML += '<div class="chat-container darker"><span class="right">' + message_json.username +   ' says:</span><hr/><p>' +  message_json.message  + '</p><span class="time-left">' + local_time_string  + '</span></div>';
       }      
      chatPanel.scrollTop = chatPanel.scrollHeight;
     }
   } catch {
     console.log(event.data + ' was not parsable');
   }
 };
 ws.onclose = function() {   // websocket is closed.
  alert("Connection is closed..."); 
};
 // Outgoing messages
 //ws.onopen = function (event) {
 //  window.setInterval(function () { count++; if ( count <= 0 ) {now = new Date(); ws.send('Hello Mojo!' + Math.floor(Math.random() * 10) );console.log( now.getTime() + ' - sending ping' + count);} }, 1000);
 //};
} else {
  alert('WebSockets not supported by this browser');
}
function send_message() { // called when button pressed
  ws.send( document.getElementById("chat-text").value );
}
</script>
</html>