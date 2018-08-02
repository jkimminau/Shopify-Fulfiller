#! /usr/bin/ruby

require 'pathname'
require 'csv'

class	Order
	
	attr_accessor :order_id, :location_id, :name, :line_items, :sku_list, :pk

	def initialize()
		@order_id = 0
		@location_id = 0
		@name = ""
		@line_items = []
		@sku_list = []
		@pk = false
	end

	def to_hash()
		return {"fulfillment" => {"location_id" => @location_id, "name" => @name, "line_items" => @line_items}}
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
		CSV.foreach(filename, {headers: true, header_converters: :symbol, converters: :all}) do |row|
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
					if (row[key] > 0)
						order.line_items << {"sku"=> key.to_s, "quantity"=> row[key]}
					end
					order.sku_list << key.to_s
				end
			end
			order.name = row[:order_id]
			order.pk = row[:pk]
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
				row[keyname] = row.delete(row.headers[0])[1]
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

	def	generate_payloads
		payloads = []
		for order in @order_list
			payloads << order.to_hash
		end
		return payloads
	end
end


def	setup_check

	content_path = Dir.pwd
	bin_path = Pathname.new(content_path + "/bin")
	keys_path = Pathname.new(content_path + "/.keys")
	filepath_path = Pathname.new(content_path + "/.path")
	error_path = Pathname.new(content_path + "/error_log")
	
	if (bin_path.exist? == false)
		system 'mkdir bin'
	end
	if (keys_path.exist? == false)
		system 'touch bin/.keys'
	end
	if (filepath_path.exist? == false)
		system 'touch bin/.path'
	end
	if (error_path.exist? == false)
		system 'touch bin/error_log'
	end

	file = ""
	File.open("bin/.keys", "r") do |f|
		f.each_line do |line|
			file += line
		end
	end
	if (file == "")
		timer 1 do
			setup_window()
		end
	end
end

def setup_window
	Shoes.app title: "Setup", width: 600, height:200, resizable: false do
		para "Enter setup info:", align: "center"
		@submit = button "Submit", top: 160, left: 225, width: 150
		para "API key:", top: 30, left: 5
		para "Password:", top: 70, left: 5
		para "Example URL:", top: 110, left: 5

		@paste_api_key = button "Paste", top: 30, left: 520
		@paste_api_secret = button "Paste", top: 70, left: 520
		@paste_shop_admin = button "Paste", top: 110, left: 520

		@api_key = edit_line top: 30, left: 115, width: 400
		@api_secret = edit_line top: 70, left: 115, width: 400
		@shop_admin = edit_line top: 110, left: 115, width: 400, height: 50
		@submit.click {
			if (@api_key.text != "" and @api_secret.text != "" and @shop_admin.text != "")
				File.open("bin/.keys", "w+") do |f|
					f.write(@api_key.text + "\n")
					f.write(@api_secret.text + "\n")
					f.write(@shop_admin.text)
				end
				close()
			end
		}
		@paste_api_key.click {
			@api_key.text = clipboard()
		}
		@paste_api_secret.click {
			@api_secret.text = clipboard()
		}
		@paste_shop_admin.click {
			@shop_admin.text = clipboard()
		}
	end
end

Shoes.app title: "EZFulfill", width: 600, height: 530, resizable: false do
	background "#cccccc"
	border("#acacac", strokewidth: 6)

	Dir.chdir ".."
	content_path = Dir.pwd
	setup_check()

	@file_button = button ("Open file")
	@file_button.move(20, 40)
	@file_disp = para("no file selected", top: 40, left: 120)
	@error_title = para("Errors:", top: 70, left: 20)
	@error_box = edit_box top: 100, left: 20, width: 560, height: 300
	@fulfill_button = button("Fulfill Orders", width: 560, top: 450, left: 20)
	@exit_button = button("Exit", top: 480, left: 20, width: 560)
	@success_msg = 0
	@keys_button = button("Re-enter authentication info", top: 10, left: 20, width: 560)
	
	parser = EZ_parser.new()
	error_txt = ""

	@file_button.click {
		if (@success_msg != 0)
			@success_msg.remove
			@success_msg = 0
		end
		filename = ask_open_file
		if (filename == nil)
			@file_disp.style(stroke: black)
			@error_title.style(stroke: black)
			@file_disp.replace "no file selected"
			@error_box.text = ""
		else
			@file_disp.replace filename
			File.open("bin/.path", "w") do |f|
				f.write(filename + "\n")
			end
		end
		error_txt = ""
		@error_title.replace "Errors:"
		if (parser.parse(filename) == false)
			@error_title.replace "Errors(#{parser.error_log.length}):"
			@file_disp.style(stroke: red)
			@error_title.style(stroke: red)
			@fulfill_button.hide()
		else
			@file_disp.style(stroke: green)
			if (parser.error_log.empty?)
				@error_title.style(stroke: green)
				error_txt = "No errors detected in .csv file\n"
				@fulfill_button.show
			else
				@error_title.style(stroke: yellow)
				@error_title.replace "Warnings (#{parser.error_log.length}):"
				@fulfill_button.show
			end
			@fulfill_button.show
		end
		parser.error_log.each do |line|
			error_txt += line + "\n"
		end
		@error_box.text = error_txt
	}

	@fulfill_button.click {
		if parser.order_list.empty? == false and @success_msg == 0
			system 'open Updater.app'
			@success_msg = para("Updates sent.", left: 20, top: 420)
		end
	}

	@keys_button.click {
		system 'rm bin/.keys'
		setup_window()
	}

	@exit_button.click {
		exit()
	}

end
