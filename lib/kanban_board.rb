require 'rubygems'
require 'yaml'
require 'json'
require 'date'

# $: << File.join(File.dirname(__FILE__), "/../../leankitkanban/lib")
require 'leankitkanban'

#mark-off all tasks in OmniFocus as done which have been moved to the 'Done' column in my LeanKit KanBan board.

class KanbanBoard

  EXTERNAL_CARD_ID = 'ExternalCardID'
  TITLE = 'Title'
  LANE_ID = 'LaneId'
  TYPE_ID = 'TypeId'
  TAGS = 'Tags'
  PRIORITY = 'Priority'
  DUE_DATE = 'DueDate'
  START_DATE = 'StartDate'
  DESCRIPTION = 'Description'
  COMPLETED = 'Completed'

  attr_reader :url, :cards

  def initialize
    config = load_config
    LeanKitKanban::Config.email = config['email']
    LeanKitKanban::Config.password = config['password']
    LeanKitKanban::Config.account = config['account']
    @board_id = config['board_id']
    @types = config['card_types']
    @completed_lanes = config['completed_lanes']
    @lane_id = get_backlog_id(config['backlog_lane_id']) # TODO - don't do this
    @url = config['board_url']
  end

  def read_board()
    @cards = []
    completed_ids = []

    backlog = []
    archive = []
    in_progress = []

    board = LeanKitKanban::Board.find(@board_id)[0]
    # puts "Looking for cards in board lanes"
    lanes = board['Lanes']
    lanes.each { |lane| in_progress.concat(read_lane(lane)) }
    # puts "Looking for cards in backlog"
    backlog.concat(read_lane(board['Backlog'][0]))
    # puts "Looking for cards in archive"
    archive.concat(read_lane(board['Archive'][0]))

    @cards.concat(backlog)
    # puts "Found #{@cards.size.to_s} cards in backlog"
    @cards.concat(in_progress)
    # puts "Found #{@cards.size.to_s} cards in backlog and in progress"
    @cards.concat(archive)
    # puts "Found #{@cards.size.to_s} cards on board"

    completed_cards = @cards.select { |c| c[COMPLETED] == true && c[EXTERNAL_CARD_ID] != "" }
    # puts "Found #{completed_cards.size.to_s} completed cards out of #{@cards.size.to_s} on board"
    completed_cards.each { |c| completed_ids << c[EXTERNAL_CARD_ID] }

    completed_ids
  end

  def add_cards(tasks)
    new_cards = []

    presynced_cards = 0
    deferred_cards = 0

    tasks.each { |task|
      start_date = task[:start_date]
      context = @types[task[:context]]
      card = {LANE_ID => @lane_id, TITLE => task[:name], TYPE_ID => context,
              EXTERNAL_CARD_ID => task[:external_id], PRIORITY => 1, DUE_DATE => task[:due_date],
              START_DATE => start_date, DESCRIPTION => task[:note]}

      if card_exists_on_board?(card)
        # puts "Ignoring pre-existing card " + task[:name]
        presynced_cards = presynced_cards + 1
      elsif start_date != nil && (Date.parse(start_date) > Date.today)
        puts "Ignoring card " + task[:name] + ". Deferred until " + start_date
        deferred_cards = deferred_cards + 1
      else
        # puts "Adding #{card[TITLE]} as type " + @types.key(context)
        # puts "\t#{card.inspect}"
        new_cards << card
      end
    }

    puts "Found #{new_cards.size.to_s} cards to sync (ignoring #{presynced_cards} already on board and #{deferred_cards} deferred)"

    if new_cards.length > 0
      puts "---"
      puts new_cards.to_json
      puts "---"

      reply = LeanKitKanban::Card.add_multiple(@board_id, "Imported from OmniFocus", new_cards)
      # puts "RESPONSE\n\t#{reply}"
    end
  end

  def clear_board()
    # puts "Clearing board..."
    # board = LeanKitKanban::Board.find(@board_id)[0]
    # board['Lanes'].each { |lane| clear_lane(lane) }
    # board['Backlog'].each { |lane| clear_lane(lane) }
  end

  def clear_lane(lane)
    card_ids = []
    lane['Cards'].each { |card|
      title = card[TITLE]
      if card[EXTERNAL_CARD_ID] != ""
        puts "removing card #{title}"
        card_ids << card['Id']
      else
        puts "ignoring non-omnifocus card #{title}"
      end
    }
    # LeanKitKanban::Card.delete_multiple(@board_id, card_ids)
  end

  def get_identifiers
    LeanKitKanban::Board.get_identifiers(@board_id)
  end

  def to_json
    LeanKitKanban::Board.find(@board_id).to_json
  end

  protected

  def read_lane(json)
    lane_title = json[TITLE]
    found_cards = []
    cards = json['Cards']
    cards.each { |card|
      id = card[EXTERNAL_CARD_ID]
      title = card[TITLE]
      done = @completed_lanes.include?(card[LANE_ID])
      found_cards << {EXTERNAL_CARD_ID => id, TITLE => title, COMPLETED => done}
      # puts "\tFound #{id}::#{title} in #{lane_title}. Is card done? #{done}"
    }

    # puts "Found #{found_cards.size.to_s} cards  in #{lane_title}"
    found_cards
  end

  def load_config()
    path = ENV['HOME'] + "/.leankit-config.yaml"
    config = YAML.load_file(path) rescue nil

    unless config
      config = {:email => "Your LeanKit username", :password => "Your LeanKit password",
                :account => "Your LeanKit account name",
                :board => "Your LeanKit board ID (copy it from https://<account>.leankit.com/boards/view/<board>)"}
      # :account => ['Done", "Deployed", "Finished", "Cards in these boards are considered done, you add and remove names to fit your workflow.'] }

      File.open(path, "w") { |f|
        YAML.dump(config, f)
      }

      abort "Created default LeanKit config in #{path}. Please complete this before re-running of-kanban"
    end

    config
  end

  def card_exists_on_board?(card)
    title = card[TITLE]
    id = card[EXTERNAL_CARD_ID]

    title_match = false #(@cards.detect { |c| c[TITLE] == title } != nil)
    id_match = (@cards.detect { |c| c[EXTERNAL_CARD_ID] == id } != nil)

    (title_match || id_match)
  end

  def get_backlog_id(id)
    if id == nil
      board = LeanKitKanban::Board.find(@board_id)[0]
      puts "No backlog ID specified, looking for default"
      id = board['Backlog'][0]['Id']
    end
    id
  end
end
