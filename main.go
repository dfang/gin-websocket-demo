package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http" // Add http package
	"text/template"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var addr = flag.String("addr", "0.0.0.0:2222", "http service address")
var hub *Hub

var upgrader = websocket.Upgrader{
	EnableCompression: false,
	CheckOrigin: func(r *http.Request) bool {
		// Allow all origins for development, tighten in production
		return true
	},
	ReadBufferSize:   1024,
	WriteBufferSize:  1024,
	HandshakeTimeout: 10 * time.Second,
}

func echo(ctx *gin.Context) {
	w, r := ctx.Writer, ctx.Request

	c, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		ctx.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to upgrade WebSocket connection",
			"details": err.Error(),
		})
		return
	}
	defer c.Close()

	client := &Client{hub: hub, conn: c, send: make(chan []byte, 256)}
	client.hub.register <- client

	// Configure more robust read timeout
	c.SetReadDeadline(time.Now().Add(30 * time.Second))

	// readLoop
	for {
		mt, message, err := c.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket read error: %v", err)
				// Optional: Add more specific error type handling
				switch {
				case websocket.IsCloseError(err):
					log.Println("WebSocket connection closed")
				case websocket.IsUnexpectedCloseError(err):
					log.Println("Unexpected WebSocket closure")
				default:
					log.Printf("Unhandled WebSocket error: %v", err)
				}
			}
			break
		}

		// Reset read deadline on successful message
		c.SetReadDeadline(time.Now().Add(30 * time.Second))

		// // Process message
		log.Printf("Received message (type %d): %s", mt, message)
		// // log.Printf("recv:%s", message)
		// err = c.WriteMessage(mt, message)
		// if err != nil {
		// 	// log.Println("write:", err)
		// 	log.Printf("WebSocket write error: %v", err)
		// 	break
		// }

		var v map[string]interface{}
		err = json.Unmarshal(message, &v)
		if err != nil {
			log.Printf("JSON unmarshal error: %v", err)
		} else {
			log.Printf("Unmarshalled message: %v", v)

			if v["type"] == "pair" {
				log.Printf("pair message received")
			}

			if v["type"] == "all_positions_closed" {
				log.Printf("stop out message received")
			}
		}
	}
}

func home(c *gin.Context) {
	homeTemplate.Execute(c.Writer, "ws://"+c.Request.Host+"/ws")
}

func main() {
	flag.Parse()
	log.SetFlags(0)

	hub = newHub()
	go hub.run()

	r := gin.Default()
	r.GET("/ws", wsWrapper(hub))
	r.GET("/", home)
	log.Fatal(r.Run(*addr))
}

var homeTemplate = template.Must(template.New("").Parse(`
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<script>  
window.addEventListener("load", function(evt) {
    var output = document.getElementById("output");
    var input = document.getElementById("input");
    var ws;
    var print = function(message) {
        var d = document.createElement("div");
        d.textContent = message;
        output.appendChild(d);
        output.scroll(0, output.scrollHeight);
    };
    document.getElementById("open").onclick = function(evt) {
        if (ws) {
            return false;
        }
        ws = new WebSocket("{{.}}");
        ws.onopen = function(evt) {
            print("OPEN");
        }
        ws.onclose = function(evt) {
            print("CLOSE");
            ws = null;
        }
        ws.onmessage = function(evt) {
            print("RESPONSE: " + evt.data);
        }
        ws.onerror = function(evt) {
            print("ERROR: " + evt.data);
        }
        return false;
    };
    document.getElementById("send").onclick = function(evt) {
        if (!ws) {
            return false;
        }
        print("SEND: " + input.value);
        ws.send(input.value);
        return false;
    };
    document.getElementById("close").onclick = function(evt) {
        if (!ws) {
            return false;
        }
        ws.close();
        return false;
    };
});
</script>
</head>
<body>
<table>
<tr><td valign="top" width="50%">
<p>Click "Open" to create a connection to the server, 
"Send" to send a message to the server and "Close" to close the connection. 
You can change the message and send multiple times.
<p>
<form>
<button id="open">Open</button>
<button id="close">Close</button>
<p><input id="input" type="text" value="Hello world!">
<button id="send">Send</button>
</form>
</td><td valign="top" width="50%">
<div id="output" style="max-height: 70vh;overflow-y: scroll;"></div>
</td></tr></table>
</body>
</html>
`))

func wsWrapper(hub *Hub) gin.HandlerFunc {
	return func(c *gin.Context) {
		w, r := c.Writer, c.Request
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println(err)
			return
		}
		client := &Client{hub: hub, conn: conn, send: make(chan []byte, 256)}
		client.hub.register <- client

		// Allow collection of memory referenced by the caller by doing all work in
		// new goroutines.
		go client.writePump()
		go client.readPump()
	}
}
