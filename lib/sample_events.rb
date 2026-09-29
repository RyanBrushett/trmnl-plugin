require "payload"

module SampleEvents
  def self.for(local_time)
    [local_time.to_date, local_time.to_date + 1].flat_map { |date| events_on(date, local_time.utc_offset) }
  end

  def self.events_on(date, utc_offset)
    at = ->(hour, minute = 0) { Time.new(date.year, date.month, date.day, hour, minute, 0, utc_offset) }

    [
      Payload::Event.new(title: "Long weekend", starts_at: at.call(0), ends_at: at.call(23, 59), all_day: true),
      Payload::Event.new(title: "Standup", starts_at: at.call(9, 30), ends_at: at.call(9, 45), work: true),
      Payload::Event.new(title: "Dentist", starts_at: at.call(15), ends_at: at.call(16)),
      Payload::Event.new(title: "Ride with Sam", starts_at: at.call(17, 30), ends_at: at.call(19)),
      Payload::Event.new(title: "Dinner at the pub", starts_at: at.call(19), ends_at: at.call(21, 30))
    ]
  end
  private_class_method :events_on
end
