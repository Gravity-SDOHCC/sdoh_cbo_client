class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "notifications"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
    # ActionCable.server.pubsub.redis_connection_for_subscriptions.srem("notifications_channel.clients", connection.client_id)
  end
end
