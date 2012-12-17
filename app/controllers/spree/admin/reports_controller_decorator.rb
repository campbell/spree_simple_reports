Spree::Admin::ReportsController.class_eval do

  before_filter :kludge_simple 
  
  def kludge_simple
    return if Spree::Admin::ReportsController::AVAILABLE_REPORTS.has_key?(:simple)
    Spree::Admin::ReportsController::AVAILABLE_REPORTS.merge!({ :simple => {:name => "Simple", :description => "Simple reporting with options"}  })
  end

  def simple
    search = params[:q] || {}
    search[:meta_sort] = "created_at asc"
    if search[:created_at_gt].blank?
      search[:created_at_gt] = Time.now - 3.months
    else
      search[:created_at_gt] = Time.zone.parse(search[:created_at_gt]).beginning_of_day rescue Time.zone.now.beginning_of_month
    end
    unless search[:created_at_lt].blank?
      search[:created_at_lt] =
          Time.zone.parse(search[:created_at_lt]).end_of_day rescue search[:created_at_lt]
    end
    @period = params[:period] || "week"
    @days = 1
    @days = 7 if @period == "week"
    @days = 30.5 if @period == "month"
    @price_or = (params[:price_or] || "total").to_sym
    search[:order_completed_at_present] = true
    search_on = case @group_by
      when "all"
        Spree::LineItem
      when "by_taxon"
        Spree::LineItem.includes(:taxon)
      when "by_product"
        Spree::LineItem
      when "by_variant"
        Spree::LineItem
      else
        Spree::LineItem.includes(:product => [:product_properties])
      end
    @search = search_on.includes(:product).ransack(search)
    @flot_options = { :series => {  :bars =>  { :show => true , :barWidth => @days * 24*60*60*1000 } , :stack => 0 } , 
                      :legend => {  :container => "#legend"} , 
                      :xaxis =>  { :mode => "time" }  
                    }
    group_data
# csv ?      send_data( render_to_string( :csv , :layout => false) , :type => "application/csv" , :filename => "tilaukset.csv") 
  end
  
  def group_data
    @group_by = (params[:group_by] || "all" )
    all = @search.result(:distinct => true )
    flot = {}
    smallest = all.first ? all.first.created_at : Time.now - 1.week
    largest = all.first ? all.last.created_at : Time.now
    if( @group_by == "all" )
      flot["all"] = all
    else
      all.each do |item|
        bucket = get_bucket(item)
        flot[ bucket ] = [] unless flot[bucket]
        flot[ bucket ] << item        
      end
    end
    @flot_data = flot.collect do |label , data |
      buck = bucket_array( data , smallest , largest )
      sum = buck.inject(0.0){|total , val | total + val[1] }
      { :label => "#{label} =#{sum}" , :data => buck } 
    end
    @flot_data.sort!{ |a,b| b[:label].split("=")[1].to_f <=> a[:label].split("=")[1].to_f }
  end
      
  def get_bucket item
    return "all" if @group_by == "all"
    case @group_by 
    when "by_taxon"
        item.variant.product.taxons.first.blank? ? "blank" : item.variant.product.taxons.first.name
    when "by_product"
        item.variant.product.name
    when "by_variant"
        item.variant.full_name
    else
      pps = item.variant.product.product_properties.detect{|p| p.property.name == @group_by}
      pps ? pps.value : "blank"
    end
  end

  # a new bucketet array version is returned 
  # a value is creted for every tick between from and two (so all arrays have same length)
  # ticks int he returned array are javascsript times ie milliseconds since 1970
  def bucket_array( array  , from , to )
    rb_tick = (@days * 24 * 60 * 60).to_i
    js_tick = rb_tick * 1000
    from = (from.to_i / rb_tick) * js_tick
    to = (to.to_i / rb_tick)* js_tick
    ret = {}
    while from <= to
      ret[from] = 0
      from += js_tick
    end
    array.each do |item|
      value = item.send(@price_or)
      index = (item.created_at.to_i / rb_tick)*js_tick
      if ret[index] == nil
        puts "No index #{index} in array (for bucketing) #{ret.to_json}" if Rails.env == "development"
        ret[index] = 0 
      end
      ret[index] = ret[index] + value
    end
    ret.sort
  end
  
end


