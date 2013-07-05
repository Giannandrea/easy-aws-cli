module CheckPoller
  def poll(msg=nil, seconds=nil, delay=nil) 
    seconds ||= 2.0                 # 5 seconds overall patience
    give_up_at = Time.now + seconds # pick a time to stop being patient
    delay = 0.1                     # wait a tenth of a second before re-attempting
    failure = nil                   # record the most recent failure

    while Time.now < give_up_at do
      result = yield
      return result if result
      sleep delay
    end
    msg ||= "polling failed after #{seconds} seconds" 
    raise msg
  end

  module_function :poll
end

class TestHelper
  include CheckPoller

  def wait_for_image(ec2, id)
    #ec2=AWS::EC2.new(:ec2_endpoint => region)
    puts "Image creation failed" and exit if ec2.images[id].state == :failed
    poll("Image didn't come online quick enough", 1800, 30) do
      ec2.images[id].state == :available
    end
  end
end

