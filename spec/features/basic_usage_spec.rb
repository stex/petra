# frozen_string_literal: true

describe 'Basic Usage' do
  # Using let() could lead to the object being created within a running transaction,
  # we therefore force it's creation before the first transaction section.
  let!(:user) do
    Classes::SimpleUser.petra.new.tap { |u| u.first_name, u.last_name = 'John', 'Doe' }
  end

  def transaction(&block)
    Petra.transaction(identifier: 'tr1', &block)
  end

  context 'with one section' do
    context 'when no write access happened yet' do
      it 'behaves exactly like the original object' do
        transaction do
          expect(user.first_name).to eql 'John'
          expect(user.last_name).to eql 'Doe'
        end
      end
    end

    context 'when changing an attribute inside the transaction' do
      context 'but not committing it' do
        it 'does not alter the original object' do
          transaction do
            user.first_name = 'Foo'
            user.save
            expect(user.first_name).to eql 'Foo'
          end

          expect(user.first_name).to eql 'John'
        end
      end

      context 'and committing it' do
        it 'alters the original object' do
          transaction do
            user.first_name = 'Foo'
            user.save
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
          transaction do
            user.first_name = 'Foo'
            expect(user.first_name).to eql 'Foo'
          end

          transaction do
            expect(user.first_name).to eql 'John'
          end
        end
      end

      context 'and persisting it' do
        it 'carries the new value over to the next section' do
          transaction do
            user.first_name = 'Foo'
            user.save
            expect(user.first_name).to eql 'Foo'
          end

          transaction do
            expect(user.first_name).to eql 'Foo'
          end
        end
      end

      context 'when altering attributes in multiple sections' do
        it 'applies all changes on commit' do
          transaction do
            user.first_name = 'Foo'
            user.save
          end

          transaction do
            user.last_name = 'Bar'
            user.save
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
