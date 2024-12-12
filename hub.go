// Copyright 2013 The Gorilla WebSocket Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package main

import (
	"log"
	"sync"
)

// Hub maintains the set of active clients and broadcasts messages to the
// clients.
type Hub struct {
	// Registered clients.
	clients map[*Client]bool

	// Clients grouped by pair identifier
	pairClients map[string]map[*Client]bool

	// Inbound messages from the clients.
	broadcast chan []byte

	// Pair-specific broadcast messages
	pairBroadcast chan PairMessage

	// Register requests from the clients.
	register chan *Client

	// Unregister requests from clients.
	unregister chan *Client

	// Mutex to protect concurrent map access
	mu sync.RWMutex
}

// PairMessage represents a message to be sent to specific pair clients
type PairMessage struct {
	PairIdentifier string
	Message        []byte
}

func newHub() *Hub {
	return &Hub{
		broadcast:     make(chan []byte),
		pairBroadcast: make(chan PairMessage),
		register:      make(chan *Client),
		unregister:    make(chan *Client),
		clients:       make(map[*Client]bool),
		pairClients:   make(map[string]map[*Client]bool),
	}
}

func (h *Hub) run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true

			// Add client to pair-specific group
			if client.pairIdentifier != "" {
				if _, exists := h.pairClients[client.pairIdentifier]; !exists {
					h.pairClients[client.pairIdentifier] = make(map[*Client]bool)
				}
				h.pairClients[client.pairIdentifier][client] = true
				log.Printf("Registered client with pair identifier: %s", client.pairIdentifier)
			}
			h.mu.Unlock()

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)

				// Remove from pair-specific group
				if client.pairIdentifier != "" {
					if pairGroup, exists := h.pairClients[client.pairIdentifier]; exists {
						delete(pairGroup, client)

						// Clean up empty pair groups
						if len(pairGroup) == 0 {
							delete(h.pairClients, client.pairIdentifier)
						}
					}
				}

				close(client.send)
			}
			h.mu.Unlock()

		case message := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				select {
				case client.send <- message:
				default:
					close(client.send)
					delete(h.clients, client)
				}
			}
			h.mu.RUnlock()

		case pairMsg := <-h.pairBroadcast:
			h.mu.RLock()
			if clients, exists := h.pairClients[pairMsg.PairIdentifier]; exists {
				for client := range clients {
					select {
					case client.send <- pairMsg.Message:
					default:
						close(client.send)
						delete(h.clients, client)
					}
				}
			}
			h.mu.RUnlock()
		}
	}
}

// BroadcastToPair sends a message to all clients with a specific pair identifier
func (h *Hub) BroadcastToPair(pairIdentifier string, message []byte) {
	h.pairBroadcast <- PairMessage{
		PairIdentifier: pairIdentifier,
		Message:        message,
	}
}
