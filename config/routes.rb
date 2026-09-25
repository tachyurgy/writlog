Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "matters#index"
  get "deadlines" => "deadlines#show", as: :deadline_calculator
  get "how-it-works" => "pages#how", as: :how_it_works

  resources :matters, only: %i[index show new create], param: :reference do
    resources :events, only: :create
    resources :communications, only: :create
    resources :documents, only: %i[index create] do
      get :preview, on: :collection
    end
  end
  resources :documents, only: :show
end
