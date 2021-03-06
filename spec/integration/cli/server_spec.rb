RSpec.describe 'hanami server', type: :cli do
  context "without routes" do
    it "shows welcome page" do
      with_project do
        server do
          visit "/"

          expect(page).to have_title("Hanami | The web, with simplicity")

          expect(page).to have_content("The web, with simplicity.")
          expect(page).to have_content("Hanami is Open Source Software for MVC web development with Ruby.")
          expect(page).to have_content("bundle exec hanami generate action web home#index --url=/")
        end
      end
    end

    it "shows welcome page for generated app" do
      with_project do
        generate "app admin"

        server do
          visit "/admin"

          expect(page).to have_content("bundle exec hanami generate action admin home#index --url=/")
        end
      end
    end
  end

  context "with routes" do
    it "serves action" do
      with_project do
        server do
          generate "action web home#index --url=/"

          visit "/"
          expect(page).to have_title("Web")
        end
      end
    end

    it "serves static asset" do
      with_project do
        server do
          write "apps/web/assets/javascripts/application.js", <<-EOF
console.log('test');
EOF
          visit "/assets/application.js"
          expect(page).to have_content("console.log('test');")
        end
      end
    end

    it "serves contents from database" do
      with_project do
        setup_model
        console do |input, _, _|
          input.puts("BookRepository.new.create(title: 'Learn Hanami')")
          input.puts("exit")
        end

        generate "action web books#show --url=/books/:id"
        rewrite  "apps/web/controllers/books/show.rb", <<-EOF
module Web::Controllers::Books
  class Show
    include Web::Action
    expose :book

    def call(params)
      @book = BookRepository.new.find(params[:id]) or halt(404)
    end
  end
end
EOF
        rewrite  "apps/web/templates/books/show.html.erb", <<-EOF
<h1><%= book.title %></h1>
EOF

        server do
          visit "/books/1"
          expect(page).to have_content("Learn Hanami")
        end
      end
    end
  end

  context "logging" do
    let(:log)     { "log/development.log" }
    let(:project) { "bookshelf" }

    context "when enabled" do
      it "logs request" do
        with_project(project) do
          touch log
          replace "config/environment.rb", "logger level: :debug", %(logger level: :debug, stream: "#{log}")

          server do
            visit "/"
            expect(page).to have_title("Hanami | The web, with simplicity")
          end

          content = contents(log)
          expect(content).to include("[#{project}] [INFO]")
          expect(content).to match(%r{HTTP/1.1 GET 200 (.*) /})
        end
      end
    end

    context "when not enabled" do
      it "does not log request" do
        with_project(project) do
          replace "config/environment.rb", "logger level: :debug", ""

          server do
            visit "/"
          end

          expect(log).to_not be_an_existing_file
        end
      end
    end
  end

  context "--host" do
    it "starts on given host" do
      with_project do
        server(host: '127.0.0.1') do
          visit "/"

          expect(page).to have_title("Hanami | The web, with simplicity")
        end
      end
    end

    xit "fails when missing" do
      with_project do
        server(host: nil)

        expect(exitstatus).to eq(1)
      end
    end
  end

  context "--port" do
    it "starts on given port" do
      with_project do
        server(port: 1982) do
          visit "/"

          expect(page).to have_title("Hanami | The web, with simplicity")
        end
      end
    end

    xit "fails when missing" do
      with_project do
        server(port: nil)

        expect(exitstatus).to eq(1)
      end
    end
  end

  context "environment" do
    it "starts with given environment" do
      with_project do
        generate "action web home#index --url=/"

        rewrite "apps/web/controllers/home/index.rb", <<-EOF
module Web::Controllers::Home
  class Index
    include Web::Action

    def call(params)
      self.body = Hanami.env
    end
  end
end
EOF

        RSpec::Support::Env['HANAMI_ENV']   = env = 'production'
        RSpec::Support::Env['DATABASE_URL'] = "sqlite://#{Pathname.new('db').join('bookshelf.sqlite')}"

        server do
          visit "/"

          expect(page).to have_content(env)
        end
      end
    end

    xit "fails when missing" do
      with_project do
        server(environment: nil)

        expect(exitstatus).to eq(1)
      end
    end
  end

  context "puma" do
    it "starts" do
      with_project('bookshelf_server_puma', server: :puma) do
        server do
          visit "/"

          expect(page).to have_title("Hanami | The web, with simplicity")
        end
      end
    end
  end

  context "unicorn" do
    it "starts" do
      with_project('bookshelf_server_unicorn', server: :unicorn) do
        server do
          visit "/"

          expect(page).to have_title("Hanami | The web, with simplicity")
        end
      end
    end
  end

  context "code reloading" do
    it "reloads templates code" do
      with_project do
        server do
          visit "/"

          expect(page).to have_title("Hanami | The web, with simplicity")
          generate "action web home#index --url=/"

          rewrite "apps/web/templates/home/index.html.erb", <<-EOF
<h1>Hello, World!</h1>
EOF

          visit "/"
          expect(page).to have_title("Web")
          expect(page).to have_content("Hello, World!")
        end
      end
    end

    it "reloads view" do
      with_project do
        server do
          visit "/"

          expect(page).to have_title("Hanami | The web, with simplicity")
          generate "action web home#index --url=/"

          rewrite "apps/web/views/home/index.rb", <<-EOF
module Web::Views::Home
  class Index
    include Web::View

    def greeting
      "Ciao!"
    end
  end
end
EOF

          rewrite "apps/web/templates/home/index.html.erb", <<-EOF
<%= greeting %>
EOF

          visit "/"
          expect(page).to have_title("Web")
          expect(page).to have_content("Ciao!")
        end
      end
    end

    it "reloads action" do
      with_project do
        server do
          visit "/"

          expect(page).to have_title("Hanami | The web, with simplicity")
          generate "action web home#index --url=/"

          rewrite "apps/web/controllers/home/index.rb", <<-EOF
module Web::Controllers::Home
  class Index
    include Web::Action

    def call(params)
      self.body = "Hi!"
    end
  end
end
EOF

          visit "/"
          expect(page).to have_content("Hi!")
        end
      end
    end

    it "reloads model" do
      project_name = "bookshelf"

      with_project(project_name) do
        # STEP 1: prepare the database and the repository
        generate_model "user"
        generate_migration "create_users", <<-EOF
Hanami::Model.migration do
  change do
    create_table :users do
      primary_key :id
      column :name, String
    end

    execute "INSERT INTO users (name) VALUES('L')"
    execute "INSERT INTO users (name) VALUES('MG')"
  end
end
EOF

        rewrite "lib/#{project_name}/repositories/user_repository.rb", <<-EOF
class UserRepository < Hanami::Repository
  def listing
    all
  end
end
EOF

        hanami "db prepare"

        # STEP 2: generate the action
        generate "action web users#index --url=/users"

        rewrite "apps/web/controllers/users/index.rb", <<-EOF
module Web::Controllers::Users
  class Index
    include Web::Action

    def call(params)
      self.body = UserRepository.new.listing.map(&:name).join(", ")
    end
  end
end
EOF

        server do
          # STEP 3: visit the page
          visit "/users"

          expect(page).to have_content("L, MG")

          # STEP 4: change the repository, then visit the page again
          rewrite "lib/#{project_name}/repositories/user_repository.rb", <<-EOF
class UserRepository < Hanami::Repository
  def listing
    all.reverse
  end
end
EOF
          visit "/users"

          expect(page).to have_content("MG, L")
        end
      end
    end

    xit "reloads asset" do
      with_project do
        server do
          write "apps/web/assets/stylesheets/style.css", <<-EOF
body { background-color: #fff; }
EOF

          visit "/assets/style.css"
          expect(page).to have_content("#fff")

          rewrite "apps/web/assets/stylesheets/style.css", <<-EOF
body { background-color: #333; }
EOF

          visit "/assets/style.css"
          expect(page).to have_content("#333")
        end
      end
    end
  end

  context "without code reloading" do
    it "doesn't reload code" do
      with_project do
        server("no-code-reloading" => nil) do
          visit "/"

          expect(page).to have_title("Hanami | The web, with simplicity")
          generate "action web home#index --url=/"

          visit "/"
          expect(page).to have_title("Hanami | The web, with simplicity")
        end
      end
    end
  end

  context "without mailer" do
    it "returns page" do
      with_project do
        remove_block "config/environment.rb", "mailer do"

        server do
          visit "/"
          expect(page).to have_title("Hanami | The web, with simplicity")
        end
      end
    end
  end
end
