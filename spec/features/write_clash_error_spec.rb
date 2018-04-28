# frozen_string_literal: true

describe 'Write Clash Error Handling' do
  let!(:user) { Classes::SimpleUser.petra.new }

  before(:each) do
    Petra.transaction(identifier: 'tr1') do
      user.first_name = 'Foo'
      user.save
    end

    user.first_name = 'Moo'
  end

  context 'when accessing an attribute that was changed both by us and externally' do
    it 'raises a WriteClashError accordingly' do
      Petra.transaction(identifier: 'tr1') do
        expect { user.first_name }.to raise_error(Petra::WriteClashError) do |e|
          expect(e.object).to eql user
          expect(e.attribute).to eql :first_name
          expect(e.our_value).to eql 'Foo'
          expect(e.external_value).to eql 'Moo'
        end
      end
    end
  end

  context 'when reacting to a WriteClashError' do
    context 'by accepting the external changes' do
      it 'discards the changes made inside the transaction' do
        Petra.transaction(identifier: 'tr1') do
          user.first_name
          expect(user.first_name).to eql 'Moo'
        rescue Petra::WriteClashError => e
          e.use_theirs!
          e.retry!
        end
      end
    end
  end
end
