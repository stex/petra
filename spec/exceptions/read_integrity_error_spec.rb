require 'spec_helper'

#
# This test does not check whether a ReadIntegrityError is thrown,
# it just tests its methods and attribute readers
#
describe Petra::ReadIntegrityError do
  let(:transaction_id_1) { Petra.transaction {} }
  let(:transaction_id_2) { Petra.transaction {} }

  around(:each) do |example|
    # Create a situation which raises a ReadIntegrityError
    user = Classes::SimpleUser.petra.new

    transaction(1) do
      @first_name, @last_name = user.first_name, user.last_name
      user.last_name
      user.save
    end

    transaction(2) do
      user.last_name = user.last_name + ' Jr.'
      user.save
      Petra.commit!
    end

    transaction(1) do
      begin
        @user = user
        user.last_name
      rescue Petra::ReadIntegrityError => e
        @exception = e
        example.run
      end
    end
  end

  #----------------------------------------------------------------
  #                        attr_accessors
  #----------------------------------------------------------------

  describe '#object' do
    it 'contains the correct object proxy as `object`' do
      expect(@exception.object).to eql @user
    end
  end

  describe '#attribute' do
    it 'contains the attribute which causes the error' do
      expect(@exception.attribute).to eql :last_name
    end
  end

  describe '#external_value' do
    it 'contains the current external value' do
      expect(@exception.external_value).to eql @user.unproxied.last_name
    end
  end

  describe '#last_read_value' do
    it 'contains the value which was last read for this attribute' do
      expect(@exception.last_read_value).to eql @last_name
    end
  end

  #----------------------------------------------------------------
  #                          #ignore!
  #----------------------------------------------------------------

  describe '#ignore!' do
    context 'with (update_value: false)' do
      before(:each) do
        @exception.ignore!(update_value: false)
      end

      it 'adds a new ObjectIntegrityOverride log entry' do
        expect(Petra.current_transaction.log_entries.last).to be_kind_of Petra::Components::Entries::ReadIntegrityOverride
      end

      it 'does not re-raise an exception if we read the attribute again' do
        expect {@user.last_name}.not_to raise_exception
      end
    end

    context 'with (update_value: true)' do
      before(:each) do
        @exception.ignore!(update_value: true)
      end

      it 'adds a new ObjectIntegrityOverride log entry' do
        expect(Petra.current_transaction.log_entries[-2]).to be_kind_of Petra::Components::Entries::ReadIntegrityOverride
      end

      it 'adds a new AttributeRead log entry for the new value' do
        entry = Petra.current_transaction.log_entries.last
        expect(entry).to be_kind_of Petra::Components::Entries::AttributeRead
        expect(entry.value).to eql @user.unproxied.last_name
      end

      it 'does not re-raise an exception if we read the attribute again' do
        expect {@user.last_name}.not_to raise_exception
      end
    end
  end

  #----------------------------------------------------------------
  #                         #rollback!
  #----------------------------------------------------------------


  #----------------------------------------------------------------
  #                          #reset!
  #----------------------------------------------------------------

  private

  def transaction(number, &block)
    Petra.transaction(identifier: send("transaction_id_#{number}"), &block)
  end

end
