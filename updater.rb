require 'csv'
require 'httparty'
require 'json'
require 'pp'

class	Order
	
	attr_accessor :order_id, :location_id, :name, :line_items, :sku_list, :pk, :refund, :refund_path

	def initialize()
		@order_id = 0
		@location_id = 0
		@name = ""
		@line_items = []
		@sku_list = []

		@pk = false
		@refund = 0
		@refund_path = ""
	end

	def fulfillment_hash()
		return {"fulfillment" => 
				{"location_id" => @location_id, "name" => @name, "line_items" => @line_items}
			}
	end

	def refund_hash(transaction_hash)
		if @pk == false
			return nil
		elsif @refund == 0
			puts "Warning for order #{@name}: Pickup value 'y' but order does not having shipping listed or does not exist."
			return nil
		end
		hash = {"refund" => {
				"shipping" => {"amount" => @refund},
				"transactions" => [{
						"parent_id" => transaction_hash["transactions"][0]["id"],
						"amount" => @refund,
						"kind" => "refund",
						"gateway" => transaction_hash["transactions"][0]["gateway"]
					}]
				}
			}
	end
end

class ClientController 
	attr_reader :base_uri, :update_list

	#This initializes the base_uri to the admin section of the store,
	#from this uri the user can go to any subsection of their store

	def initialize()
		dir_path = Dir.pwd
		dir_path.slice! "Updater.app/Contents/Resources"
		
		keys = []
		File.open(dir_path + "/bin/.keys", "r") do |f|
			f.each_line do |line|
				keys << line.chomp()
			end
		end
		@@API_KEY = keys[0]
		@@API_SECRET = keys[1]
		keys[2].slice! "https://" + keys[0] + ":" + keys[1] + "@"
		keys[2].slice! "/orders.json"
		@@SHOP_ADMIN = keys[2]
		@base_uri = "https://#{@@API_KEY}:#{@@API_SECRET}@#{@@SHOP_ADMIN}"
	end

    #Allows you to construct a target uri of the form:
    #base_uri/resource_table/resource/destination.json
    #base_uri/resource_table/destination.json, since destination is hard
    #coded right now it should always be the former, however we can easily modify
    #our program later to find any resource or table target

	def construct_resource_uri(resource_table, resource = "", destination = "")
		uri = [@base_uri, resource_table, resource].join('/')

		if destination.empty? 
			resource_uri = uri[0..-2] + '.json'
		else
			resource_uri = uri + "/#{destination}.json"
		end
	end

    #Gets one of the top level tables like products or orders from the database
    #returns a hash_table of all current orders in the store in this case

	def get_resource_table(target_uri)
		response = HTTParty.get(target_uri)
		data = response.body.to_s
		resource_hash = JSON.parse data
		return resource_hash
	end

    #From the table we pulled earlier, we're going to extract all of one kind of
    #keys value like "id" or "email" and stores the key type as the first member
    #in the list as a string.

	def get_all_keys_for_resource(hash_resource, key, search_list)
		val_list = [key]
		resource_name = hash_resource.keys()[0].to_s.tr("[]", "")
		for h in hash_resource[resource_name]
			if search_list.include? h["name"]
				val_list.push(h[key])
			end
		end
		return val_list
	end

	def get_info_for_orders(order_list, hash_resource)
        	resource_name = hash_resource.keys()[0].to_s.tr("[]", "")
		for order in order_list
			for h in hash_resource[resource_name]
				if order.name == h["name"]
					total_weight = h["total_weight"]
					order.order_id = h["id"]
					order.location_id = h["location_id"]
					fulfill_weight = 0.0
					for item in order.line_items
						for hitem in h["line_items"]
							if item["sku"] == hitem["sku"] or item["sku"] == hitem["title"]
								fulfill_weight += hitem["grams"] * item["quantity"]
								item["id"] = hitem["id"]
								item.delete("sku")
							end
						end
					end
					refund_per = (100 * (fulfill_weight / total_weight)).to_i
					if (h["shipping_lines"][0] != nil)
						order.refund = '%.2f' % (h["shipping_lines"][0]["price"].to_f * refund_per / 100)
					end
				end
			end
		end
	end	

    #This function will be extended to check and see if the given resource key type
    #from the previous example is a writable table itself or a writable value
    #in that table and determine the integerity of the user's intent 
    #(e.g. has one to many or many to many or one to one relationships)

	def check_is_writable(resource_id)
		return true
	end

    #This function builds the uri path to the resource you would like to make
    #an update to, in essence, everything you searched for in the "get_all_keys_for_resource"
    #will be trimmed down to what you want to update and then the pathways
    #to those updates will be constructed

	def build_update_pathways(resource_table, resource_ids)
		resource_is_writable = self.check_is_writable(resource_ids[0])
		path_list = [resource_table]
		for resource_id in resource_ids.drop(1)
			path_list.push(self.construct_resource_uri(resource_table, resource_id, "fulfillments"))
		end
		return path_list
	end
end

class LocalUpdate 
	include HTTParty
	attr_reader :call_limit_token
	attr_accessor :updates, :error_log
	attr_reader :destination

    #Starts by setting up the header and creating an array of hashes
    #in the form of path=>payload as updates

	def initialize(path_list = [], json_payloads = [])
		@call_limit_token  = "http_x_shopify_shop_api_call_limit"
		@destination = "/fulfillments.json"
		@updates = []
		@headers = {'Content-Type'=>'application/json'}
		@error_log = []
		path_list.zip(json_payloads).each do |path , payload|
			@updates.push({path => payload})
		end
	end

    #This function checks the api call limit

	def get_api_call_stack(token)
		puts token
		if token == "39/40" or token == "40/40"
			true
		end
	end

    #One by one this function post the payload(update[target_uri]) 
    #to the target uri with the headers. The default wait cycle
    #is 10 seconds (5 requests fall out) before resuming if you get
    #to 39/40 calls. The cycle, controls the time between posts
    #for shopify this is 0.5 seconds

	def post_updates(wait = 10, cycle = 2)
		puts "Pushing fulfillments...\n"
		@updates.each do |update|
			target_uri = update.keys()[0].to_s.tr("[]" ,"")

			response =  HTTParty.post(target_uri, :headers => {'Content-Type'=>'application/json'}, :body => update[target_uri].to_json)

			reduce_rate = get_api_call_stack(response.headers[@call_limit_token])
			if (response.to_s.include? "error")
				puts "Order #{update[target_uri]["fulfillment"]["name"]}: " + response.to_s + "\n"
			else
				puts "Order #{update[target_uri]["fulfillment"]["name"]}: successfully updated.\n"
			end
 
			if reduce_rate == true
				sleep(wait)
			else
				sleep(cycle)
			end
		end
		puts "Finished pushing fulfillments..."
	end

	def post_refunds(refund_updates, wait = 10, cycle = 2)
		if refund_updates == []
			puts "No refunds detected"
			return
		end
		puts "Pushing refunds...\n"
		refund_updates.each do |update|
			target_uri = update.keys()[0].to_s.tr("[]" ,"")

			response =  HTTParty.post(target_uri, :headers => {'Content-Type'=>'application/json'}, :body => update[target_uri].to_json)

			reduce_rate = get_api_call_stack(response.headers[@call_limit_token])
			
			if (response.to_s.include? "errors")
				puts response #"Order #{update[target_uri]["fulfillment"]["name"]}: " + response.to_s + "\n"
			else
				puts "Refund successfully made."
			end

			if reduce_rate == true
				sleep(wait)
			else
				sleep(cycle)
			end
		end
		puts "Finished pushing refunds..."
	end
end

class	EZ_parser
	attr_accessor :order_list, :error_log

	def	initialize()
		@order_list = []
		@error_log = []
	end	


	def	parse(filename)
		@error_log = []
		@order_list = []
		error_status = true
		if (File.extname(filename) != '.csv')
			@error_log << "Error: file '#{filename}' is not a .csv file"
			return false
		end
		line = 2
		#CSV.foreach(filename, {headers: true, header_converters: :symbol, converters: :all}) do |row|
		CSV.foreach(filename, {headers: true, converters: :all}) do |row|
			order = Order.new
			if key_check(row, line) == false
				return false
			end
			line_items = Array.new
			row.headers.each do |key|
				if (key == :order_id and order_id_check(row, line) == false)
					error_status = false
				elsif (key == :pk and pickup_check(row, line) == false)
					error_status = false
				elsif (key != :order_id and key != :pk)
					if quantity_check(row, key, line) == false
						error_status = false
					end
					if ((row[key].is_a? String) == false and row[key] > 0)
						order.line_items << {"sku"=> key.to_s, "quantity"=> row[key]}
					end
					order.sku_list << key.to_s
				end
			end
			order.name = row[:order_id]
			order.pk = (row[:pk] == nil) ? false : row[:pk]
			@order_list << order
			line += 1
		end
		if error_status == false
			@order_list = []
		end
		return error_status ? true : false
	end

	def	key_check(row, line)
		l = 0
		order_col = false
		pickup_col = false
		while (l < row.headers.length)
			key = row.headers[0].to_s
			keyname = row.headers[0].to_s.downcase
			if (keyname == "")
				@error_log << "Error (line 1): empty header, please correct your file"
				return false
			elsif (['order_id', 'order id', 'order', 'order num', 'order_num', 'order number', 'order_number', 'ordernum'].include? keyname) == true
				row[:order_id] = row.delete(row.headers[0])[1]
				if (order_col == false)
					order_col = true
				else
					@error_log << "Error (line 1): too many headers match 'order_id', please correct your file"
					return false
				end
			elsif (['pk', 'pickup', 'self pickup', 'self_pickup', 'self-pickup'].include? keyname) == true
				row[:pk] = row.delete(row.headers[0])[1]
				if (pickup_col == false)
					pickup_col = true
				else
					@error_log << "Error (line 1): too many headers match 'pickup', please correct your file"
					return false
				end
			else
				row[key] = row.delete(row.headers[0])[1]
			end
			l += 1
		end
		if order_col == false
			@error_log << "Error (line 1): Missing 'order_id' header, please correct your file."
		end
		if pickup_col == false
			@error_log << "Warning (line 1): Missing 'pickup' header, please correct your file."
		end
		return order_col #and pickup_col) ? true : false
	end

	def	order_id_check(row, line)
		if (row[:order_id] == nil)
			@error_log << "Error (line #{line}): Missing 'order_id' value, please correct your file."
			return false
		elsif ((row[:order_id].is_a? String) == false)
			@error_log << "Error (line #{line}): 'ordernum' value '#{row[:order_id].to_s}' is invalid, please correct your file."
			return false
		end
		return true
	end

	def	pickup_check(row, line)
		if row[:pk] == nil
			@error_log << "Warning (line #{line}):  Missing 'pickup' value for order_id #{row[:order_id]}, correcting value to 'n'"
			row[:pk] = 'n'
		elsif (((row[:pk].is_a? String) == false) or (row[:pk] != 'n' and row[:pk] != 'y'))
			@error_log << "Error (line #{line}): 'pickup' value '#{row[:pk].to_s}' for order_id #{row[:order_id]} is invalid, please correct your file"
			return false
		end
		if row[:pk] == 'y'
			row[:pk] = true
		elsif row[:pk] == 'n'
			row[:pk] = false
		end
		return true
	end

	def	quantity_check(row, key, line)
		if (row[key] == nil)
			@error_log << "Warning (line #{line}): Missing #{key} value for order_id #{row[:order_id]}, correcting value to 0"
			row[key] = 0
		elsif ((row[key].is_a? Integer) == false or (row[key].is_a? Integer and row[key] < 0))
			@error_log << "Error (line #{line}): 'quantity' value '#{row[key].to_s}' is invalid, please correct your file."
			return false
		end
		return true
	end
	
	def	generate_search_list
		search_list = []
		for order in @order_list
			search_list << order.name
		end
		return search_list
	end

	def	generate_id_list
		id_list = ["id"]
		for order in @order_list
			id_list << order.order_id
		end
		return id_list
	end

	def	generate_fulfillments
		payloads = []
		for order in @order_list
			payloads << order.fulfillment_hash
		end
		return payloads
	end
end

#COMMAND LINE FUNCTION

dir_path = Dir.pwd
dir_path.slice! "Updater.app/Contents/Resources"

filename = ""
File.open(dir_path + "/bin/.path", "r") do |f|
	f.each_line do |line|
		filename << line.chomp()
	end
end

parser = EZ_parser.new()
parser.parse(filename)

f = ClientController.new()
uri = f.construct_resource_uri("orders")

resource_hash = f.get_resource_table(uri)
search_list = parser.generate_search_list()

f.get_info_for_orders(parser.order_list, resource_hash)
id_list = parser.generate_id_list

path_list = f.build_update_pathways("orders", id_list)
json_payloads = parser.generate_fulfillments()


l = LocalUpdate.new(path_list.drop(1), json_payloads)

l.post_updates()

puts "\n"

refund_updates = []
for order in parser.order_list
	transaction_uri = f.construct_resource_uri("orders/" + order.order_id.to_s + "/transactions")
	transaction_hash = f.get_resource_table(transaction_uri)
	refund = order.refund_hash(transaction_hash)
	order.refund_path = f.construct_resource_uri("orders/" + order.order_id.to_s + "/refunds");
	if refund != nil
		refund_updates.push({order.refund_path => refund})
	end
end

l.post_refunds(refund_updates)
