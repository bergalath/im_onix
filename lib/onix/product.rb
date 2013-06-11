require 'onix/helper'
require 'onix/code'
require 'onix/entity'
require 'onix/descriptive_detail'
require 'onix/publishing_detail'
require 'onix/collateral_detail'
require 'onix/related_material'
require 'onix/supporting_resource'
require 'onix/subject'
require 'onix/contributor'
require 'onix/product_supply'
require 'onix/territory'
require 'onix/error'

module ONIX
  class Product < Subset
    attr_accessor :notification_type,
                  :identifiers,
                  :related_material,
                  :descriptive_detail,
                  :publishing_detail,
                  :collateral_detail,
                  :product_supplies

    include EanMethods

    def initialize
      @identifiers=[]
      @product_supplies=[]
    end

    def contributors
      @descriptive_detail.contributors
    end

    def title
      @descriptive_detail.title
    end

    def subtitle
      @descriptive_detail.subtitle
    end

    def description
      if @collateral_detail
        @collateral_detail.description
      else
        nil
      end
    end

    def raw_description
      if self.description
        self.description.gsub(/\s+/," ")
      else
        nil
      end
    end

    def publisher
      if @publishing_detail
        @publishing_detail.publisher
      else
        nil
      end
    end

    def publisher_name
      if self.publisher
        self.publisher.name
      else
        nil
      end
    end

    def imprint
      if @publishing_detail
        @publishing_detail.publisher
      else
        nil
      end
    end

    def imprint_name
      if self.imprint
        self.imprint.name
      else
        nil
      end
    end

    def distributors
      @product_supplies.map{|ps| ps.distributors}.flatten.uniq{|d| d.name}
    end

    def distributor
      if self.distributors.length > 0
      if self.distributors.length==1
        self.distributors.first
      else
        raise ExpectsOneButHasSeveral, self.distributors.map(&:name)
      end
      else
        nil
      end
    end

    def distributor_name
      if self.distributor
        self.distributor.name
      else
        nil
      end
    end

    def paper_linking
      @related_material.paper_linking
    end

    def publication_date
      @publishing_detail.publication_date
    end

    def countries_rights
      countries=[]
      if @publishing_detail
        countries+=@publishing_detail.sales_rights.map{|sr| sr.territory.countries}.flatten.uniq
      end

      if @product_supplies
        countries+=@product_supplies.map{|ps| ps.markets.map{|m| m.territory.countries}.flatten}.flatten.uniq
      end

      countries.uniq
    end

    # flattened prices
    def prices
      prices=[]

      # add territories if missing
      if @product_supplies
        @product_supplies.each do |ps|
          ps.supply_details.each do |sd|
            sd.prices.each do |p|
              cp=p.dup
              if !cp.territory or cp.territory.countries.length==0
                cp.territory=Territory.new
                if ps.markets
                  cp.territory.countries=ps.markets.map{|m| m.territory.countries}.flatten.uniq
                end
                if cp.territory.countries.length==0
                  if @publishing_detail
                    cp.territory.countries=self.countries_rights
                  end
                end
              end
              prices << cp
            end
          end
        end
      end

      # merge territories
      grouped_prices={}
      prices.each do |pr|
        pr_key="#{pr.type.code}#{pr.from_date}#{pr.until_date}#{pr.currency}#{pr.amount}"
        grouped_prices[pr_key]||=pr
        grouped_prices[pr_key].territory.countries+=pr.territory.countries
      end

      prices=grouped_prices.to_a.map{|h| h.last}

      grouped_prices={}
      prices.each do |pr|
        pr_key="#{pr.type.code}#{pr.currency}#{pr.territory.countries.join(',')}"
        grouped_prices[pr_key]||=[]
        grouped_prices[pr_key] << pr
      end

      # render prices sequentially with dates
      grouped_prices.each do |kpr, pr|
        if pr.length > 1
#          puts "MULTIPRICES"
          global_price=pr.select{|p| not p.from_date and not p.until_date}
#          pp global_price
          global_price=global_price.first
          if global_price
#            puts "FOUND GLOBAL"
            pr.each do |p|
              if p!=global_price
                if p.from_date
                  pd=PriceDate.new
                  pd.role=PriceDateRole.from_human("UntilDate")
                  pd.date=p.from_date
                  global_price.dates << pd
#                  puts "GLOBAL"
#                  pp global_price
                end

                if p.until_date
                  np=global_price.dup
                  pd=PriceDate.new
                  pd.role=PriceDateRole.from_human("FromDate")
                  pd.date=p.until_date
                  np.dates << pd
                  pr << np
                end

              end
            end
          else
            # remove explicit from date
            explicit_from=pr.select{|p| p.from_date and not pr.select{|sp| sp.until_date==p.from_date}.first}.first
            if explicit_from
              explicit_from.dates=explicit_from.dates.delete_if{|p| p.role.human=="FromDate"}
            end
          end
        end
      end

      prices=grouped_prices.to_a.map{|h| h.last}.flatten

      prices
    end

    def prices_including_tax
      self.prices.select{|p| p.including_tax?}
    end


    def parse(p)
      if p.at("./NotificationType")
        @notification_type=NotificationType.from_code(p.at("./NotificationType").text)
      end

      @identifiers=Identifier.parse_identifiers(p,"Product")

      # RelatedMaterial

      related=p.at("./RelatedMaterial")
      if related
        @related_material=RelatedMaterial.from_xml(related)
      end

      # DescriptiveDetail
      descriptive=p.at("./DescriptiveDetail")
      if descriptive
        @descriptive_detail=DescriptiveDetail.from_xml(descriptive)
      end

      # CollateralDetail
      collateral=p.at("./CollateralDetail")
      if collateral
        @collateral_detail=CollateralDetail.from_xml(collateral)
      end

      # PublishingDetail
      publishing = p.at("./PublishingDetail")
      if publishing
        @publishing_detail=PublishingDetail.from_xml(publishing)
      end

      # ProductSupply
      p.search("./ProductSupply").each do |ps|
        @product_supplies << ProductSupply.from_xml(ps)
      end
    end
  end
end