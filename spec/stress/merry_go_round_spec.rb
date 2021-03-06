require "spec_helper"

describe "A message that is proxied by multiple intermediate consumers" do
  let(:c1) do
    c = Bunny.new(username: "bunny_gem",
      password: "bunny_password",
      vhost: "bunny_testbed",
      heartbeat_timeout: 6)
    c.start
    c
  end

  let(:c2) do
    c = Bunny.new(username: "bunny_gem",
      password: "bunny_password",
      vhost: "bunny_testbed",
      heartbeat_timeout: 6)
    c.start
    c
  end

  let(:c3) do
    c = Bunny.new(username: "bunny_gem",
      password: "bunny_password",
      vhost: "bunny_testbed",
      heartbeat_timeout: 6)
    c.start
    c
  end

  let(:c4) do
    c = Bunny.new(username: "bunny_gem",
      password: "bunny_password",
      vhost: "bunny_testbed",
      heartbeat_timeout: 6)
    c.start
    c
  end

  let(:c5) do
    c = Bunny.new(username: "bunny_gem",
      password: "bunny_password",
      vhost: "bunny_testbed",
      heartbeat_timeout: 6)
    c.start
    c
  end

  after :each do
    [c1, c2, c3, c4, c5].each do |c|
      c.close if c.open?
    end
  end

  # message flow is as follows:
  #
  # x => q4 => q3 => q2 => q1 => xs (results)
  it "reaches its final destination" do
    n   = 50_000
    xs  = []

    ch1 = c1.create_channel
    q1  = ch1.queue("", exclusive: true)
    q1.subscribe(manual_ack: true) do |delivery_info, _, payload|
      xs << payload
      ch1.ack(delivery_info.delivery_tag)
    end

    ch2 = c2.create_channel
    q2  = ch2.queue("", exclusive: true)
    q2.subscribe do |_, _, payload|
      q1.publish(payload)
    end

    ch3 = c3.create_channel(nil, 2)
    q3  = ch3.queue("", exclusive: true)
    q3.subscribe(manual_ack: true) do |delivery_info, _, payload|
      q2.publish(payload)
      ch3.ack(delivery_info.delivery_tag)
    end

    ch4 = c4.create_channel(nil, 4)
    q4  = ch4.queue("", exclusive: true)
    q4.subscribe do |_, _, payload|
      q3.publish(payload)
    end

    ch5 = c5.create_channel(nil, 8)
    x   = ch5.default_exchange

    n.times do |i|
      x.publish("msg #{i}", routing_key: q4.name)
    end

    Bunny::TestKit.poll_until(40) do
      xs.size >= n
    end

    expect(xs.size).to eq n
    expect(xs.last).to eq "msg #{n - 1}"
  end
end
