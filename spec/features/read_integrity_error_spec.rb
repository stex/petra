# frozen_string_literal: true

describe 'Read Integrity Error Handling' do
  let!(:user) { Classes::SimpleUser.petra.new('Karl') }

  before(:each) do
    Petra.transaction(identifier: 'tr1') do
      user.last_name = 'the first' if user.first_name == 'Karl'
      user.save
    end

    user.first_name = 'Olaf'
  end

  context 'when re-reading an attribute which was changed externally' do
    it 'raises a ReadIntegrityError accordingly' do
      Petra.transaction(identifier: 'tr1') do
        expect { user.first_name }.to raise_error(Petra::ReadIntegrityError) do |e|
          expect(e.object).to eql user
          expect(e.attribute).to eql :first_name
          expect(e.external_value).to eql 'Olaf'
          expect(e.last_read_value).to eql 'Karl'
        end
      end
    end
  end

  context 'when reacting to a ReadIntegrityError' do
    context 'by simply not doing anything' do
      it 'raises the error again the next time' do
        Petra.transaction(identifier: 'tr1') do
          begin
            user.first_name # raises an exception
            expect { user.first_name }.to raise_error Petra::ReadIntegrityError
          rescue Petra::ReadIntegrityError => e
            e.continue!
          end
        end
      end
    end

    context 'by ignoring the change' do
      it 'does not raise an exception for the the same external value again' do
        Petra.transaction(identifier: 'tr1') do
          begin
            user.first_name # raises an exception
            expect { user.first_name }.not_to raise_error Petra::ReadIntegrityError
          rescue Petra::ReadIntegrityError => e
            e.ignore!
            e.continue!
          end
        end
      end

      context 'and updating the value inside the transaction' do
        it 'ignores the external change, but applies the new value' do
          Petra.transaction(identifier: 'tr1') do
            begin
              user.first_name = 'Gustav' if user.first_name == 'Olaf'
              expect(user.first_name).to eql 'Gustav'
            rescue Petra::ReadIntegrityError => e
              e.ignore!(update_value: true)
              e.continue!
            end
          end
        end
      end

      context 'and keeping our old value' do
        it 'ignores the external change and the new value' do
          Petra.transaction(identifier: 'tr1') do
            begin
              user.first_name = 'Gustav' if user.first_name == 'Olaf'
              expect(user.first_name).to eql 'Karl'
            rescue Petra::ReadIntegrityError => e
              e.ignore!(update_value: false)
              e.continue!
            end
          end
        end
      end
    end
  end
end
