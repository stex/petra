# frozen_string_literal: true

describe 'Basic Usage' do
  let(:user) { Classes::SimpleUser.new }

  def transaction(&block)
    Petra.transaction(identifier: 'tr1', &block)
  end

  context 'with one section' do
    context 'when no write access happened yet' do
      it 'behaves exactly like the original object' do
        transaction do
          expect(user.petra.first_name).to eql user.first_name
          expect(user.petra.last_name).to eql user.last_name
        end
      end
    end

    context 'when changing an attribute inside the transaction' do
      context 'but not committing it' do
        it 'does not alter the original object' do
          transaction do
            user.petra.first_name = 'Foo'
            user.petra.save
            expect(user.petra.first_name).to eql 'Foo'
          end

          expect(user.first_name).not_to eql 'Foo'
        end
      end

      context 'and committing it' do
        it 'alters the original object' do
          transaction do
            user.petra.first_name = 'Foo'
            user.petra.save
            Petra.commit!
          end

          expect(user.first_name).to eql 'Foo'
        end
      end
    end
  end

  context 'with multiple sections' do
    context 'when altering an attribute' do
      context 'and not persisting it' do
        it 'does not carry the new value over to the next section' do
          original_name = user.first_name

          transaction do
            user.petra.first_name = 'Foo'
            expect(user.petra.first_name).to eql 'Foo'
          end

          transaction do
            expect(user.petra.first_name).to eql original_name
          end
        end
      end

      context 'and persisting it' do
        it 'carries the new value over to the next section' do
          transaction do
            user.petra.first_name = 'Foo'
            user.petra.save
            expect(user.petra.first_name).to eql 'Foo'
          end

          transaction do
            expect(user.petra.first_name).to eql 'Foo'
          end
        end
      end

      context 'when altering attributes in multiple sections' do
        it 'applies all changes on commit' do
          transaction do
            user.petra.first_name = 'Foo'
            user.petra.save
          end

          transaction do
            user.petra.last_name = 'Bar'
            user.petra.save
          end

          transaction do
            Petra.commit!
          end

          expect(user).to have_attributes(first_name: 'Foo', last_name: 'Bar')
        end
      end
    end
  end
end
