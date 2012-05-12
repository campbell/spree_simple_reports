Spree::Core::Engine.routes.draw do
  match '/admin/reports/simple' => 'admin/reports#simple' , 
                      :as => "simple_admin_reports",  :via  => [:get, :post]
end

