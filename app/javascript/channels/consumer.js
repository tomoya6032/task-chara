// Action Cable provides the framework to deal with WebSockets in Rails.
// You can generate new channels where WebSocket features live using the `bin/rails generate channel` command.

import { createConsumer } from "@rails/actioncable"

// Initialize ActionCable consumer
const consumer = createConsumer()

// Make consumer available globally as App.cable
window.App = window.App || {}
window.App.cable = consumer

export default consumer