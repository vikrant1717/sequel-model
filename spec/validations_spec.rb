require File.join(File.dirname(__FILE__), "spec_helper")

describe "Sequel::Validatable::Errors" do
  setup do
    @errors = Sequel::Validatable::Errors.new
    class Sequel::Validatable::Errors
      attr_accessor :errors
    end
  end
  
  specify "should be clearable using #clear" do
    @errors.errors = {1 => 2, 3 => 4}
    @errors.clear
    @errors.errors.should == {}
  end
  
  specify "should be empty if no errors are added" do
    @errors.should be_empty
    @errors[:blah] << "blah"
    @errors.should_not be_empty
  end
  
  specify "should return errors for a specific attribute using #on or #[]" do
    @errors[:blah].should == []
    @errors.on(:blah).should == []

    @errors[:blah] << 'blah'
    @errors[:blah].should == ['blah']
    @errors.on(:blah).should == ['blah']

    @errors[:bleu].should == []
    @errors.on(:bleu).should == []
  end
  
  specify "should accept errors using #[] << or #add" do
    @errors[:blah] << 'blah'
    @errors[:blah].should == ['blah']
    
    @errors.add :blah, 'zzzz'
    @errors[:blah].should == ['blah', 'zzzz']
  end
  
  specify "should return full messages using #full_messages" do
    @errors.full_messages.should == []
    
    @errors[:blow] << 'blieuh'
    @errors[:blow] << 'blich'
    @errors[:blay] << 'bliu'
    msgs = @errors.full_messages
    msgs.size.should == 3
    msgs.should include('blow blieuh', 'blow blich', 'blay bliu')
  end
end

describe Sequel::Validatable do
  setup do
    @c = Class.new do
      include Sequel::Validatable
      
      def self.validates_coolness_of(attr)
        validates_each(attr) {|o, a, v| o.errors[a] << 'is not cool' if v != :cool}
      end
    end
    
    @d = Class.new do
      attr_accessor :errors
      def initialize; @errors = Sequel::Validatable::Errors.new; end
    end
  end
  
  specify "should respond to validates, validations, has_validations?" do
    @c.should respond_to(:validations)
    @c.should respond_to(:has_validations?)
  end
  
  specify "should acccept validation definitions using validates_each" do
    @c.validates_each(:xx, :yy) {|o, a, v| o.errors[a] << 'too low' if v < 50}
    
    @c.validations[:xx].size.should == 1
    @c.validations[:yy].size.should == 1
    
    o = @d.new
    @c.validations[:xx].first.call(o, :aa, 40)
    @c.validations[:yy].first.call(o, :bb, 60)
    
    o.errors.full_messages.should == ['aa too low']
  end

  specify "should return true/false for has_validations?" do
    @c.has_validations?.should == false
    @c.validates_each(:xx) {1}
    @c.has_validations?.should == true
  end
  
  specify "should provide a validates method that takes block with validation definitions" do
    @c.validates do
      coolness_of :blah
    end
    @c.validations[:blah].should_not be_empty

    o = @d.new
    @c.validations[:blah].first.call(o, :ttt, 40)
    o.errors.full_messages.should == ['ttt is not cool']
    o.errors.clear
    @c.validations[:blah].first.call(o, :ttt, :cool)
    o.errors.should be_empty
  end
end

describe "A Validatable instance" do
  setup do
    @c = Class.new do
      attr_accessor :score
      
      include Sequel::Validatable
      
      validates_each :score do |o, a, v|
        o.errors[a] << 'too low' if v < 87
      end
    end
    
    @o = @c.new
  end
  
  specify "should supply a #valid? method that returns true if validations pass" do
    @o.score = 50
    @o.should_not be_valid
    @o.score = 100
    @o.should be_valid
  end
  
  specify "should provide an errors object" do
    @o.score = 100
    @o.should be_valid
    @o.errors.should be_empty
    
    @o.score = 86
    @o.should_not be_valid
    @o.errors[:score].should == ['too low']
    @o.errors[:blah].should be_empty
  end
end

describe Sequel::Validatable::Generator do
  setup do
    $testit = nil
    
    @c = Class.new do
      include Sequel::Validatable
      
      def self.validates_blah
        $testit = 1324
      end
    end
  end
  
  specify "should instance_eval the block, sending everything to its receiver" do
    Sequel::Validatable::Generator.new(@c) do
      blah
    end
    $testit.should == 1324
  end
end

describe "Sequel validations" do
  setup do
    @c = Class.new do
      attr_accessor :value
      include Sequel::Validatable
    end
    @m = @c.new
  end

  specify "should validate acceptance_of" do
    @c.validates_acceptance_of :value
    @m.should be_valid
    @m.value = '1'
    @m.should be_valid
  end
  
  specify "should validate acceptance_of with accept" do
    @c.validates_acceptance_of :value, :accept => 'true'
    @m.value = '1'
    @m.should_not be_valid
    @m.value = 'true'
    @m.should be_valid
  end
  
  specify "should validate acceptance_of with allow_nil => false" do
    @c.validates_acceptance_of :value, :allow_nil => false
    @m.should_not be_valid
  end

  specify "should validate confirmation_of" do
    @c.send(:attr_accessor, :value_confirmation)
    @c.validates_confirmation_of :value
    
    @m.value = 'blah'
    @m.should_not be_valid
    
    @m.value_confirmation = 'blah'
    @m.should be_valid
  end

  specify "should validate format_of" do
    @c.validates_format_of :value, :with => /.+_.+/
    @m.value = 'abc_'
    @m.should_not be_valid
    @m.value = 'abc_def'
    @m.should be_valid
  end
  
  specify "should raise for validate_format_of without regexp" do
    proc {@c.validates_format_of :value}.should raise_error(Sequel::Error)
    proc {@c.validates_format_of :value, :with => :blah}.should raise_error(Sequel::Error)
  end
  
  specify "should validate length_of with maximum" do
    @c.validates_length_of :value, :maximum => 5
    @m.should_not be_valid
    @m.value = '12345'
    @m.should be_valid
    @m.value = '123456'
    @m.should_not be_valid
  end

  specify "should validate length_of with minimum" do
    @c.validates_length_of :value, :minimum => 5
    @m.should_not be_valid
    @m.value = '12345'
    @m.should be_valid
    @m.value = '1234'
    @m.should_not be_valid
  end

  specify "should validate length_of with within" do
    @c.validates_length_of :value, :within => 2..5
    @m.should_not be_valid
    @m.value = '12345'
    @m.should be_valid
    @m.value = '1'
    @m.should_not be_valid
    @m.value = '123456'
    @m.should_not be_valid
  end

  specify "should validate length_of with is" do
    @c.validates_length_of :value, :is => 3
    @m.should_not be_valid
    @m.value = '123'
    @m.should be_valid
    @m.value = '12'
    @m.should_not be_valid
    @m.value = '1234'
    @m.should_not be_valid
  end
  
  specify "should validate length_of with allow_nil" do
    @c.validates_length_of :value, :is => 3, :allow_nil => true
    @m.should be_valid
  end

  specify "should validate numericality_of" do
    @c.validates_numericality_of :value
    @m.value = 'blah'
    @m.should_not be_valid
    @m.value = '123'
    @m.should be_valid
    @m.value = '123.1231'
    @m.should be_valid
  end

  specify "should validate numericality_of with only_integer" do
    @c.validates_numericality_of :value, :only_integer => true
    @m.value = 'blah'
    @m.should_not be_valid
    @m.value = '123'
    @m.should be_valid
    @m.value = '123.1231'
    @m.should_not be_valid
  end
  
  specify "should validate presence_of" do
    @c.validates_presence_of :value
    @m.should_not be_valid
    @m.value = ''
    @m.should_not be_valid
    @m.value = 1234
    @m.should be_valid
  end
end

describe Sequel::Model, "Validations" do

  before(:all) do
    class Person < Sequel::Model(:people)
      def columns
        [:id,:name,:first_name,:last_name,:middle_name,:initials,:age, :terms]
      end
    end

    class Smurf < Person
    end
    
    class Cow < Sequel::Model(:cows)
      def columns
        [:id, :name, :got_milk]
      end
    end

    class User < Sequel::Model(:users)
      def columns
        [:id, :username, :password]
      end
    end
    
    class Address < Sequel::Model(:addresses)
      def columns
        [:id, :zip_code]
      end
    end
  end
  
  it "should validate the acceptance of a column" do
    class Cow < Sequel::Model(:cows)
      validations.clear
      validates_acceptance_of :got_milk, :accept => 'blah', :allow_nil => false
    end
    
    @cow = Cow.new
    @cow.should_not be_valid
    @cow.errors.full_messages.should == ["got_milk is not accepted"]
    
    @cow.got_milk = "blah"
    @cow.should be_valid
  end
  
  it "should validate the confirmation of a column" do
    class User < Sequel::Model(:users)      
      def password_confirmation
        "test"
      end
      
      validations.clear
      validates_confirmation_of :password
    end
    
    @user = User.new
    @user.should_not be_valid
    @user.errors.full_messages.should == ["password is not confirmed"]
    
    @user.password = "test"
    @user.should be_valid
  end
  
  it "should validate format of column" do
    class Person < Sequel::Model(:people)  
      validates_format_of :first_name, :with => /^[a-zA-Z]+$/
    end

    @person = Person.new :first_name => "Lancelot99"
    @person.valid?.should be_false
    @person = Person.new :first_name => "Anita"
    @person.valid?.should be_true
  end
  
  # it "should allow for :with_exactly => /[a-zA-Z]/, which wraps the supplied regex with ^<regex>$" do
  #   pending("TODO: Add this option to Validatable#validates_format_of")
  # end

  it "should validate length of column" do
    class Person < Sequel::Model(:people)
      validations.clear
      validates_length_of :first_name, :maximum => 30
      validates_length_of :last_name, :minimum => 30
      validates_length_of :middle_name, :within => 1..5
      validates_length_of :initials, :is => 2
    end
    
    @person = Person.new(
      :first_name => "Anamethatiswaytofreakinglongandwayoverthirtycharacters",
      :last_name => "Alastnameunderthirtychars",
      :initials => "LGC",
      :middle_name => "danger"
    )
    
    @person.should_not be_valid
    @person.errors.full_messages.size.should == 4
    @person.errors.full_messages.should include(
      'first_name is too long',
      'last_name is too short',
      'middle_name is the wrong length',
      'initials is the wrong length'
    )
    
    @person.first_name  = "Lancelot"
    @person.last_name   = "1234567890123456789012345678901"
    @person.initials    = "LC"
    @person.middle_name = "Will"
    @person.should be_valid
  end
  
  it "should validate numericality of column" do
    class Person < Sequel::Model(:people)
      validations.clear
      validates_numericality_of :age
    end
    
    @person = Person.new :age => "Twenty"
    @person.should_not be_valid
    @person.errors.full_messages.should == ['age is not a number']
    
    @person.age = 20
    @person.should be_valid
  end
  
  it "should validate the presence of a column" do
    class Cow < Sequel::Model(:cows)
      validations.clear
      validates_presence_of :name
    end
    
    @cow = Cow.new
    @cow.should_not be_valid
    @cow.errors.full_messages.should == ['name is not present']
    
    @cow.name = "Betsy"
    @cow.should be_valid
  end
  
  it "should have a validates block that calls multple validations" do
    class Person < Sequel::Model(:people)
      validations.clear
      validates do
        format_of :first_name, :with => /^[a-zA-Z]+$/
        length_of :first_name, :maximum => 30
      end
    end

    Person.validations[:first_name].size.should == 2
    
    @person = Person.new :first_name => "Lancelot99"
    @person.valid?.should be_false
    
    @person2 = Person.new :first_name => "Wayne"
    @person2.valid?.should be_true
  end

  it "should allow 'longhand' validations direcly within the model." do
    lambda {
      class Person < Sequel::Model(:people)
        validations.clear
        validates_length_of :first_name, :maximum => 30
      end
    }.should_not raise_error
    Person.validations.length.should eql(1)
  end

  it "should define a has_validations? method which returns true if the model has validations, false otherwise" do
    class Person < Sequel::Model(:people)
      validations.clear
      validates do
        format_of :first_name, :with => /\w+/
        length_of :first_name, :maximum => 30
      end
    end

    class Smurf < Person
      validations.clear
    end

    Person.should have_validations
    Smurf.should_not have_validations
  end
end

describe "Model#save!" do
  setup do
    @c = Class.new(Sequel::Model(:people)) do
      def columns; [:id]; end
      
      validates_each :id do |o, a, v|
        o.errors[a] << 'blah' unless v == 5
      end
    end
    @m = @c.new(:id => 4)
    MODEL_DB.reset
  end
  
  specify "should save regardless of validations" do
    @m.should_not be_valid
    @m.save!
    MODEL_DB.sqls.should == ['UPDATE people SET id = 4 WHERE (id = 4)']
  end
end

describe "Model#save!" do
  setup do
    @c = Class.new(Sequel::Model(:people)) do
      def columns; [:id]; end

      validates_each :id do |o, a, v|
        o.errors[a] << 'blah' unless v == 5
      end
    end
    @m = @c.new(:id => 4)
    MODEL_DB.reset
  end

  specify "should save only if validations pass" do
    @m.should_not be_valid
    @m.save
    MODEL_DB.sqls.should be_empty
    
    @m.id = 5
    @m.should be_valid
    @m.save
    MODEL_DB.sqls.should == ['UPDATE people SET id = 5 WHERE (id = 5)']
  end
  
  specify "should return false if validations fail" do
    @m.save.should == false
  end
end