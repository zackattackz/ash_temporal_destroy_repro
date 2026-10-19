defmodule Repro.Blog do
  use Ash.Domain, otp_app: :repro

  resources do
    resource Repro.Blog.Post do
      define :update_post, action: :update
      define :destroy_post, action: :destroy
    end
  end
end
