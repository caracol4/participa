require 'test_helper'

class ElectionTest < ActiveSupport::TestCase

  test "should validate presence on election" do 
    e = Election.new
    e1 = Election.new(title: "hola mundo", agora_election_id: 1, starts_at: DateTime.now, ends_at: DateTime.now + 2.weeks, scope: 0)
    e.valid?
    assert(e.errors[:title].include? "no puede estar en blanco")
    assert(e.errors[:agora_election_id].include? "no puede estar en blanco")
    assert(e.errors[:starts_at].include? "no puede estar en blanco")
    assert(e.errors[:ends_at].include? "no puede estar en blanco")
    assert(e.errors[:scope].include? "no puede estar en blanco")
    assert e1.valid?
  end

  test "should scope :active work" do 
    e1 = FactoryGirl.create(:election, starts_at: DateTime.civil(1999, 2, 2, 12, 12), ends_at: DateTime.civil(2001, 2, 2, 12, 12))
    assert e1.valid?
    assert_equal(Election.active.count, 0)
    e2 = FactoryGirl.create(:election, starts_at: DateTime.civil, ends_at: DateTime.now + 2.weeks)
    assert e2.valid?
    assert_equal(Election.active.count, 1)
  end

  test "should .is_active? work" do 
    # votacion ya cerrada
    e1 = FactoryGirl.create(:election, starts_at: DateTime.now-30.days, ends_at: DateTime.now-7.days)
    assert_not e1.is_active?

    # votacion activa
    e2 = FactoryGirl.create(:election, starts_at: DateTime.now-30.days, ends_at: DateTime.now+7.days)
    assert e2.is_active?

    # votacion del futuro, todavia no esta activada
    e3 = FactoryGirl.create(:election, starts_at: DateTime.now+30.days, ends_at: DateTime.now+90.days)
    assert_not e3.is_active?
  end

  test "should recently_finished? work" do 
    e = FactoryGirl.create(:election)
    e.update_attributes(starts_at: DateTime.now-90.days, ends_at: DateTime.now+7.days)
    assert_not e.recently_finished?
    e.update_attributes(ends_at: DateTime.now-30.days)
    assert_not e.recently_finished?
    e.update_attributes(ends_at: DateTime.now-36.hours)
    assert e.recently_finished?
  end

  test "should .has_valid_location_for? work" do 
    # Si es una eleccion estatal todos participan
    election = FactoryGirl.create(:election)

    user = FactoryGirl.create(:user, vote_town: "m_28_079_6")
    assert election.has_valid_location_for? user

    # si es municipal solo los que esten en ese municipio
    election = FactoryGirl.create(:election, :town)
    assert election.has_valid_location_for? user

    # si es municipal no permitir a los que no esten en ese municipio
    election.election_locations[0].location = "222222"
    assert_not election.has_valid_location_for? user
  end

  test "should .scope_name work" do 
    election = FactoryGirl.create(:election)
    election.update_attributes(scope: 0)
    assert_equal(election.scope_name, "Estatal")
    election.update_attributes(scope: 1)
    assert_equal(election.scope_name, "Comunidad")
    election.update_attributes(scope: 2)
    assert_equal(election.scope_name, "Provincial")
    election.update_attributes(scope: 3)
    assert_equal(election.scope_name, "Municipal")
  end

  test "should .scoped_agora_election_id work" do 
    election = FactoryGirl.create(:election)
    user = FactoryGirl.create(:user)
    assert_equal(1000, election.scoped_agora_election_id(user))

    election = FactoryGirl.create(:election, :autonomy)
    assert_equal(1111, election.scoped_agora_election_id(user))

    election = FactoryGirl.create(:election, :province)
    assert_equal(1280, election.scoped_agora_election_id(user))
    
    election = FactoryGirl.create(:election, :town)
    assert_equal(12807960, election.scoped_agora_election_id(user))

    user = FactoryGirl.create(:user, :island)
    election = FactoryGirl.create(:election, :island_election)
    assert_equal(1730, election.scoped_agora_election_id(user))

    user = FactoryGirl.create(:user, :foreign_address)
    election = FactoryGirl.create(:election, :foreign_election)
    assert_equal(1000, election.scoped_agora_election_id(user))
  end

  test "should full_title_for work" do 
    user = FactoryGirl.create(:user)
    user2 = FactoryGirl.create(:user, town: "m_01_001_4")

    election = FactoryGirl.create(:election)
    assert_equal("Hola mundo", election.full_title_for(user))
    assert_equal("Hola mundo", election.full_title_for(user2))
    
    election = FactoryGirl.create(:election, :autonomy)
    assert_equal("Hola mundo en Comunidad de Madrid", election.full_title_for(user))
    assert_equal("Hola mundo (no hay votación en País Vasco/Euskadi)", election.full_title_for(user2))

    election = FactoryGirl.create(:election, :town)
    assert_equal("Hola mundo en Madrid", election.full_title_for(user))
    assert_equal("Hola mundo (no hay votación en Alegría-Dulantzi)", election.full_title_for(user2))

  end

  test "should locations work" do 
    election = FactoryGirl.create(:election, :town)
    election.election_locations << FactoryGirl.create(:election_location, election: election, location: 280797, agora_version: 1)
    election.election_locations << FactoryGirl.create(:election_location, election: election, location: 280798, agora_version: 0)
    assert_equal( "280796,0\n280797,1\n280798,0", election.locations )
  end

  test "should locations= work" do 
    election = FactoryGirl.create(:election)
    election.locations = "280796,0\n280797,0\n280798,0"
    election.save
    assert_equal( "280796,0\n280797,0\n280798,0", election.locations )

    election.locations = "280796,0\n280797,1\n280799,0"
    election.save
    assert_equal( "280796,0\n280797,1\n280799,0", election.locations )

    el = ElectionLocation.where(election: election.id, location: 280797).first
    assert_equal(1, el.agora_version)
    assert_equal("280797", el.location)
  end

end
