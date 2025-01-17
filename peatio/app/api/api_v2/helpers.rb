# encoding: UTF-8
# frozen_string_literal: true

module APIv2
  module Helpers
    extend Memoist

    def authenticate!
      current_user or raise Peatio::Auth::Error
    end

    def deposits_must_be_permitted!
      if current_user.level < ENV.fetch('MINIMUM_MEMBER_LEVEL_FOR_DEPOSIT').to_i
        raise Error.new(text: 'Please, pass the corresponding verification steps to deposit funds.', status: 401)
      end
    end

    def withdraws_must_be_permitted!
      if current_user.level < ENV.fetch('MINIMUM_MEMBER_LEVEL_FOR_WITHDRAW').to_i
        raise Error.new(text: 'Please, pass the corresponding verification steps to withdraw funds.', status: 401)
      end
    end

    def trading_must_be_permitted!
      if current_user.level < ENV.fetch('MINIMUM_MEMBER_LEVEL_FOR_TRADING').to_i
        raise Error.new(text: 'Please, pass the corresponding verification steps to enable trading.', status: 401)
      end
    end

    def current_user
      # JWT authentication provides member email.
      if env.key?('api_v2.authentic_member_email')
        Member.find_by_email(env['api_v2.authentic_member_email'])
      end
    end
    memoize :current_user

    def current_market
      Market.enabled.find_by_id(params[:market])
    end
    memoize :current_market

    def time_to
      params[:timestamp].present? ? Time.at(params[:timestamp]) : nil
    end

    def build_order(attrs)
      (attrs[:side] == 'sell' ? OrderAsk : OrderBid).new \
        state:         ::Order::WAIT,
        member:        current_user,
        ask:           current_market&.base_unit,
        bid:           current_market&.quote_unit,
        market:        current_market,
        ord_type:      attrs[:ord_type] || 'limit',
        price:         attrs[:price],
        volume:        attrs[:volume],
        origin_volume: attrs[:volume]
    end

    def create_order(attrs)
      order = build_order(attrs)
      Ordering.new(order).submit
      order
    rescue Account::AccountError => e
      report_exception_to_screen(e)
      raise CreateOrderAccountError, e.inspect
    rescue => e
      report_exception_to_screen(e)
      raise CreateOrderError, e.inspect
    end

    def create_orders(multi_attrs)
      orders = multi_attrs.map(&method(:build_order))
      Ordering.new(orders).submit
      orders
    rescue => e
      report_exception_to_screen(e)
      raise CreateOrderError, e.inspect
    end

    def order_param
      params[:order_by].downcase == 'asc' ? 'id asc' : 'id desc'
    end

    def format_ticker(ticker)
      permitted_keys = %i[buy sell low high open last volume
                            avg_price price_change_percent]

      # Add vol for compatibility with old API.
      formatted_ticker = ticker.slice(*permitted_keys)
                           .merge(vol: ticker[:volume])
      { at: ticker[:at],
        ticker: formatted_ticker }
    end

    RESOLUTION_PERIOD_MAP = {
        '1': 1,
        '15': 15,
        '30': 30,
        '60': 60,
        'D': 1440,
        '1D': 1440
    }.as_json

    def resolution_to_period(resolution)
      RESOLUTION_PERIOD_MAP[resolution]
    end

    def convert_klines_to_bars(klines = [])
      t, o, h, l, c, v = klines.transpose
      {
          s: 'ok', :t => t, :o => o, :h => h, :l => l, :c => c, :v => v
      }
    end
  end
end
