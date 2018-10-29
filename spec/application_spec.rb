RSpec.describe LePain::Application do
  it 'does not fail' do
    expect { described_class.new.load }.not_to raise_exception
  end
end
