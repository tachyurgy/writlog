class ApplicationController < ActionController::Base
  allow_browser versions: :modern, block: ->(*) { true } # never block; this is a public demo
  rescue_from ActiveRecord::RecordNotFound do
    render plain: "Not found", status: :not_found
  end

  private

  def find_matter
    @matter = Matter.find_by!(reference: params[:matter_reference] || params[:reference])
  end
end
