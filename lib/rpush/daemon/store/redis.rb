module Rpush
  module Daemon
    module Store
      class Redis
        include Rpush::Client::Redis

        DEFAULT_MARK_OPTIONS = { persist: true }

        def initialize
          @redis = Modis.redis
        end

        def all_apps
          App.all
        end

        def deliverable_notifications(apps)
          batch_size = Rpush.config.batch_size
          results = @redis.multi do
            @redis.zrange(Notification.absolute_pending_namespace, 0, batch_size)
            @redis.zremrangebyrank(Notification.absolute_pending_namespace, 0, batch_size)
          end
          ids = results.first
          ids.map { |id| Notification.find(id) }
        end

        def mark_delivered(notification, time, opts = {})
          opts = DEFAULT_MARK_OPTIONS.dup.merge(opts)
          notification.delivered = true
          notification.delivered_at = time

          if opts[:persist]
            notification.save!(validate: false)
          end
        end

        def mark_batch_delivered(notifications)
          now = Time.now
          notifications.each { |n| mark_delivered(n, now) }
        end

        def mark_failed(notification, code, description, time, opts = {})
          opts = DEFAULT_MARK_OPTIONS.dup.merge(opts)
          notification.delivered = false
          notification.delivered_at = nil
          notification.failed = true
          notification.failed_at = time
          notification.error_code = code
          notification.error_description = description

          if opts[:persist]
            notification.save!(validate: false)
          end
        end

        def mark_batch_failed(notifications, code, description)
          now = Time.now
          notifications.each { |n| mark_failed(n, code, description, now) }
        end

        def mark_retryable(notification, deliver_after, opts = {})
          opts = DEFAULT_MARK_OPTIONS.dup.merge(opts)
          notification.retries += 1
          notification.deliver_after = deliver_after

          if opts[:persist]
            notification.save!(validate: false)
          end
        end

        def mark_batch_retryable(notifications, deliver_after)
          notifications.each { |n| mark_retryable(n, deliver_after) }
        end

        def create_apns_feedback(failed_at, device_token, app)
          Apns::Feedback.create!(failed_at: failed_at, device_token: device_token, app: app)
        end

        def create_gcm_notification(attrs, data, registration_ids, deliver_after, app)
          notification = Gcm::Notification.new
          create_gcm_like_notification(notification, attrs, data, registration_ids, deliver_after, app)
        end

        def create_adm_notification(attrs, data, registration_ids, deliver_after, app)
          notification = Adm::Notification.new
          create_gcm_like_notification(notification, attrs, data, registration_ids, deliver_after, app)
        end

        def update_app(app)
          app.save!
        end

        def update_notification(notification)
          notification.save!
        end

        def release_connection
          @redis.client.disconnect
        end

        def after_daemonize
        end

        private

        def create_gcm_like_notification(notification, attrs, data, registration_ids, deliver_after, app)
          notification.assign_attributes(attrs)
          notification.data = data
          notification.registration_ids = registration_ids
          notification.deliver_after = deliver_after
          notification.app = app
          notification.save!
          notification
        end
      end
    end
  end
end

Rpush::Daemon::Store::Interface.check(Rpush::Daemon::Store::Redis)
