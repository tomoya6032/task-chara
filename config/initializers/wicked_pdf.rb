# WickedPDF Global Configuration
#
# Use this to set up shared configuration options for your entire application.
# Any of the configuration options shown here can also be applied to single
# models by passing arguments to the `render :pdf` call.
#
# To learn more, check out the README:
#
# https://github.com/mileszs/wicked_pdf/blob/master/README.md

WickedPdf.configure do |c|
  # Path to the wkhtmltopdf executable: This usually isn't needed if using
  # one of the wkhtmltopdf-binary family of gems.
  # c.exe_path = '/usr/local/bin/wkhtmltopdf'
  #   or
  # c.exe_path = Gem.bin_path('wkhtmltopdf-binary', 'wkhtmltopdf')

  # Layout file to be used for all PDFs
  # (but can be overridden in `render :pdf` calls)
  # c.layout = 'pdf.html'

  # Enable Local File Access for CSS and images
  c.enable_local_file_access = true

  # Using wkhtmltopdf without an X server can be achieved by enabling xvfb
  # c.use_xvfb = true
end
