require 'ears/configuration'

RSpec.describe Ears::Configuration do
  it 'has a default rabbitmq url' do
    expect(Ears::Configuration.new.rabbitmq_url).to eq(
      'amqp://guest:guest@localhost:5672',
    )
  end

  it 'allows setting the rabbitmq url' do
    configuration = Ears::Configuration.new
    configuration.rabbitmq_url = 'test'

    expect(configuration.rabbitmq_url).to eq('test')
  end
end
