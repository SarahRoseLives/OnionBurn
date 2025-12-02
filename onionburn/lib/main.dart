import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tor_hidden_service/tor_hidden_service.dart';

// --- CONFIGURATION ---
const int _localChatPort = 8080; // Local port for the HttpServer
const String _title = 'OnionBurn';

// --- HTML/JAVASCRIPT FOR THE CHAT INTERFACE ---
// This is the HTML page served by the hidden service.
// It uses JavaScript to establish a WebSocket connection back to the server.
const String _chatHtml = r"""
<!DOCTYPE html>
<html>
<head>
    <title>Onion Chat</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Arial, sans-serif; background-color: #222; color: #eee; margin: 0; padding: 10px; }
        #chat-window { height: 300px; overflow-y: auto; border: 1px solid #444; padding: 10px; margin-bottom: 10px; background-color: #333; }
        #input-box { display: flex; }
        #message-input { flex-grow: 1; padding: 10px; border: 1px solid #444; background-color: #555; color: white; }
        #send-button { padding: 10px 15px; background-color: #6a1b9a; color: white; border: none; cursor: pointer; }
        .log-msg { color: #aaa; font-size: 0.8em; }
        .peer-msg { color: #81c784; }
        .self-msg { color: #64b5f6; }
    </style>
</head>
<body>
    <h3>OnionBurn</h3>
    <div id="chat-window"></div>
    <div id="input-box">
        <input type="text" id="message-input" placeholder="Type message..." />
        <button id="send-button">Send</button>
    </div>

    <script>
        const chatWindow = document.getElementById('chat-window');
        const messageInput = document.getElementById('message-input');
        const sendButton = document.getElementById('send-button');
        let ws;

        // The WebSocket connection MUST use the address the browser is currently on
        // and the port it accessed the web page on (which Tor maps to 80).
        const wsUrl = `ws://${window.location.host}/ws`;

        function log(message, className = 'log-msg') {
            const p = document.createElement('p');
            p.className = className;
            p.textContent = message;
            chatWindow.appendChild(p);
            chatWindow.scrollTop = chatWindow.scrollHeight;
        }

        function connect() {
            log('Attempting to connect via WebSocket...');
            ws = new WebSocket(wsUrl);

            ws.onopen = () => {
                log('Connection established! Ready to chat.', 'log-msg');
                messageInput.disabled = false;
                sendButton.disabled = false;
            };

            ws.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);
                    if (data.type === 'chat') {
                        log(`Peer: ${data.message}`, 'peer-msg');
                    }
                } catch (e) {
                    log('Error parsing message.', 'log-msg');
                }
            };

            ws.onclose = () => {
                log('Connection closed by host.', 'log-msg');
                messageInput.disabled = true;
                sendButton.disabled = true;
            };

            ws.onerror = (error) => {
                log('WebSocket Error.', 'log-msg');
            };
        }

        function sendMessage() {
            const message = messageInput.value.trim();
            if (message && ws && ws.readyState === WebSocket.OPEN) {
                const chatMessage = JSON.stringify({
                    type: 'chat',
                    message: message
                });
                ws.send(chatMessage);
                log(`You: ${message}`, 'self-msg');
                messageInput.value = '';
            }
        }

        sendButton.onclick = sendMessage;
        messageInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                sendMessage();
            }
        });
        
        connect();
    </script>
</body>
</html>
""";

// --- MAIN APPLICATION WIDGET ---
void main() {
  runApp(const TorChatApp());
}

class TorChatApp extends StatelessWidget {
  const TorChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _title,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

// --- CHAT SCREEN STATEFUL WIDGET ---
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _torService = TorHiddenService();
  final List<String> _messages = [];
  final TextEditingController _messageController = TextEditingController();

  // State Variables
  bool _isTorRunning = false;
  String? _onionHostname; // The address to share
  WebSocket? _remoteWebSocket; // The established browser connection
  HttpServer? _localServer; // Listens for incoming connections

  @override
  void initState() {
    super.initState();
    _startTor();
  }

  // --- 1. START TOR AND HOST SERVICE ---
  Future<void> _startTor() async {
    _torService.onLog.listen((log) {
      if (log.contains('Bootstrapped 100%')) {
        _log('Tor is bootstrapped and ready!');
        setState(() => _isTorRunning = true);
        _startHiddenService();
      }
    });

    try {
      _log('Starting Tor...');
      await _torService.start();
    } catch (e) {
      _log('Error starting Tor: $e');
    }
  }

  Future<void> _startHiddenService() async {
    try {
      // Start a local HTTP server that will be exposed by the Hidden Service
      _localServer = await HttpServer.bind('127.0.0.1', _localChatPort);
      _localServer!.listen(_handleIncomingRequest);
      _log('Local Server listening on port $_localChatPort...');

      // Get the publicly visible Onion Address
      final hostname = await _torService.getOnionHostname();

      setState(() {
        _onionHostname = hostname;
      });
      _log('Ready to Host! Share this address: http://$_onionHostname');
      _log('Waiting for browser connection...');
    } catch (e) {
      _log('Error hosting service: $e');
      _shutdown();
    }
  }

  // --- 2. HANDLE INCOMING BROWSER CONNECTION (HTTP & WS) ---
  Future<void> _handleIncomingRequest(HttpRequest request) async {
    // 1. Check if the client is asking for the WebSocket upgrade
    // FIX: Changed 'is upgrading' to the correct method 'isUpgradeRequest'
    if (request.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      if (_remoteWebSocket != null) {
        request.response.statusCode = HttpStatus.conflict;
        await request.response.close();
        _log('Connection rejected: Already in a chat session.');
        return;
      }

      // Upgrade the connection to a WebSocket
      _remoteWebSocket = await WebSocketTransformer.upgrade(request);
      _log('WebSocket session established with browser!');
      setState(() => _messages.add('--- SESSION ESTABLISHED (BROWSER CONNECTED) ---'));

      // Listen for messages from the browser
      _remoteWebSocket!.listen(
        _handleIncomingData,
        onError: _handleSocketError,
        onDone: () {
          _log('Browser disconnected.');
          _remoteWebSocket = null;
          setState(() => _messages.add('--- SESSION LOST (BROWSER CLOSED) ---'));
        },
      );

      // Send a welcome message to the browser
      _sendRawMessage('{"type":"status", "message":"Connected to Flutter Host."}');

    }
    // 2. Serve the initial HTML page
    else if (request.uri.path == '/') {
      request.response
        ..headers.contentType = ContentType.html
        ..write(_chatHtml);
      await request.response.close();
      _log('Served chat interface to browser.');
    }
    // 3. Handle other requests
    else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  // --- 3. CHAT COMMUNICATION ---

  // Handle incoming data from the WebSocket (the browser)
  void _handleIncomingData(dynamic data) {
    try {
      if (data is String) {
        final messageData = json.decode(data);
        if (messageData['type'] == 'chat') {
          setState(() {
            _messages.add('Peer (Browser): ${messageData['message']}');
          });
        }
      }
    } catch (e) {
      _log('Failed to parse incoming data: $e');
    }
  }

  // Send message from the Flutter app to the browser
  void _sendMessage() {
    if (_remoteWebSocket == null) {
      _log('Not connected to a browser peer.');
      return;
    }
    if (_messageController.text.isEmpty) return;

    final message = _messageController.text;
    _messageController.clear();

    final chatMessage = json.encode({
      'type': 'chat',
      'message': message, // Fixed the key here to be 'message'
    });

    _sendRawMessage(chatMessage);
    setState(() {
      _messages.add('You (Phone): $message');
    });
  }

  void _sendRawMessage(String data) {
    try {
      _remoteWebSocket!.add(data);
    } catch (e) {
      _handleSocketError(e);
    }
  }

  void _handleSocketError(dynamic e) {
    _log('WebSocket error: $e. Session closed.');
    setState(() {
      _messages.add('--- SESSION LOST ---');
      _remoteWebSocket = null;
    });
  }

  // --- 4. SHUTDOWN AND CLEANUP ("THROWAWAY") ---
  Future<void> _shutdown() async {
    _log('Shutting down session and deleting Onion keys...');

    // Close all connections
    await _remoteWebSocket?.close();
    await _localServer?.close(force: true);

    // CRITICAL: Stop Tor and delete the ephemeral hidden service key
    await _torService.stop();

    setState(() {
      _isTorRunning = false;
      _onionHostname = null;
      _remoteWebSocket = null;
      _messages.clear();
      _messages.add('--- SESSION DESTROYED ---');
    });
  }

  // --- 5. UI AND LOGGING ---
  void _log(String message) {
    print('APP: $message');
    if (mounted) {
      setState(() {
        _messages.add('LOG: $message');
      });
    }
  }

  @override
  void dispose() {
    _shutdown();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _shutdown,
            tooltip: 'End Chat & Delete Onion',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.deepPurple.shade900,
            child: Row(
              children: [
                Icon(_isTorRunning ? Icons.security : Icons.sync,
                    color: _isTorRunning ? Colors.greenAccent : Colors.orange),
                const SizedBox(width: 8),
                Text(
                  _isTorRunning ? 'Tor Ready' : 'Bootstrapping Tor...',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // Onion Address Display
          if (_onionHostname != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText(
                'Share Link: http://$_onionHostname',
                style: const TextStyle(fontSize: 14, color: Colors.amber),
              ),
            ),

          // Message Log/Chat Display
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 4.0, horizontal: 8.0),
                  child: Text(message),
                );
              },
            ),
          ),
          const Divider(height: 1),

          // Message Input (for phone-to-browser messages)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      labelText: 'Type message to browser...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (text) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}