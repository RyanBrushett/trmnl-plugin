require "trmnl/liquid"

# Renders templates/shared.liquid + templates/full.liquid locally, for previews
# and tests, using TRMNL's own Liquid engine so the template tag, the file
# system and the filters behave as they do on TRMNL.
class Template
  PATH = File.expand_path("../templates/full.liquid", __dir__)
  SHARED_PATH = File.expand_path("../templates/shared.liquid", __dir__)
  FRAMEWORK_CSS = "https://trmnl.com/css/latest/plugins.css"
  FRAMEWORK_JS = "https://trmnl.com/js/latest/plugins.js"

  def initialize(path: PATH, shared_path: SHARED_PATH)
    # TRMNL puts the shared markup in front of the layout: "A in Shared and B
    # in Full displays AB", so the two files are joined with nothing between.
    source = File.read(shared_path) + File.read(path)
    @liquid = Liquid::Template.parse(source, environment: TRMNL::Liquid.new)
  end

  def render(body)
    @liquid.render!(body.fetch("merge_variables"), strict_variables: true, strict_filters: true)
  end

  # TRMNL supplies the screen and view wrappers around our layout.
  def preview_page(body)
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="#{FRAMEWORK_CSS}">
          <script src="#{FRAMEWORK_JS}"></script>
        </head>
        <body class="environment trmnl">
          <div class="screen screen--ogv2">
            <div class="view view--full">
              #{render(body)}
            </div>
          </div>
        </body>
      </html>
    HTML
  end
end
