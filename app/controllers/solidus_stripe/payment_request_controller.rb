# frozen_string_literal: true

module SolidusStripe
  class PaymentRequestController < Spree::BaseController
    include Spree::Core::ControllerHelpers::Order

    def shipping_rates
      rates = SolidusStripe::ShippingRatesService.new(
        current_order,
        current_user,
        params[:shipping_address]
      ).call

      taxes = Spree::TaxCalculator::Default.new(current_order).calculate.line_item_taxes
      tax_total_amount = Integer(taxes.first&.amount.to_d * 100)

      order_items = (
        current_order.line_items.map { |l| { label: 'Subtotal', amount: Integer(l.total_before_tax * 100) }} + 
        [ { label: "Tax", amount: tax_total_amount } ] +
        [ { label: "Shipping", amount: rates.first[:amount] } ] +
        current_order.adjustments.select { |a| !a.amount.zero? } .map { |a| { label: a.label, amount: Integer(a.amount * 100) }}
      )

      if rates.any?
        render json: { success: true, shipping_rates: rates, label: "Teleport", amount: (current_order.total * 100).to_i + rates.first[:amount] + tax_total_amount, items: order_items }
      else
        render json: { success: false, error: 'No shipping method available for that address' }, status: 500
      end
    end

    def update_order
      current_order.restart_checkout_flow

      address = SolidusStripe::AddressFromParamsService.new(
        shipping_address_from_params,
        current_user
      ).call

      if address.valid?
        SolidusStripe::PrepareOrderForPaymentService.new(address, self, current_user).call

        if current_order.payment?
          render json: { success: true }
        else
          render json: { success: false, error: 'Order not ready for payment. Try manual checkout.' }, status: 500
        end
      else
        render json: { success: false, error: address.errors.full_messages.to_sentence }, status: 500
      end
    end

    private

    def shipping_address_from_params
      return {} unless params[:shipping_address]
      return params[:shipping_address] if params.dig(:shipping_address, :phone).present?

      params[:shipping_address][:phone] = params[:phone]
      params[:shipping_address]
    end
  end
end
