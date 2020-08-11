# frozen_string_literal: true

module Jobs
  class DiscoursePostEventSendReminder < ::Jobs::Base
    sidekiq_options retry: false

    def execute(args)
      raise Discourse::InvalidParameters.new(:event_id) if args[:event_id].blank?
      raise Discourse::InvalidParameters.new(:reminder) if args[:reminder].blank?

      event = DiscoursePostEvent::Event.includes(post: [:topic], invitees: [:user]).find(args[:event_id])
      invitees = event.invitees.where(status: DiscoursePostEvent::Invitee.statuses[:going])

      already_notified_users = Notification.where(
        read: false,
        notification_type: Notification.types[:custom],
        topic_id: event.post.topic_id,
        post_number: 1
      )

      event_started = Time.now > event.starts_at

      # we remove users who have been visiting the topic since event started
      if event_started
        invitees = invitees.where.not(
          user_id: TopicUser
            .where('topic_users.topic_id = ? AND topic_users.last_visited_at >= ? AND topic_users.last_read_post_number >= ?', event.post.topic_id, event.starts_at, 1)
            .pluck(:user_id)
            .concat(already_notified_users.pluck(:user_id))
        )
      else
        invitees = invitees.where.not(user_id: already_notified_users.pluck(:user_id))
      end

      invitees.find_each do |invitee|
        invitee.user.notifications.create!(
          notification_type: Notification.types[:custom],
          topic_id: event.post.topic_id,
          post_number: event.post.post_number,
          data: {
            topic_title: event.post.topic.title,
            display_username: invitee.user.username,
            message: "discourse_post_event.notifications.#{event_started ? 'after' : 'before'}_event_reminder"
          }.to_json
        )
      end
    end
  end
end