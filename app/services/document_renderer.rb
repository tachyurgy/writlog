require "prawn"

# Merges values into a template body and renders two artifacts: sanitized HTML
# for the in-app preview and a PDF (Prawn, pure Ruby, so the runtime image needs
# no headless browser or native PDF toolchain).
module DocumentRenderer
  module_function

  def merge(body, values)
    body.gsub(DocumentTemplate::FIELD) { values.fetch(Regexp.last_match(1)) }
  end

  def html(body, values)
    escaped = ERB::Util.html_escape(body).to_str
    merged = escaped.gsub(DocumentTemplate::FIELD) { %(<mark>#{ERB::Util.html_escape(values.fetch(Regexp.last_match(1)))}</mark>) }
    merged.split(/\n{2,}/).map { |para| "<p>#{para.gsub("\n", '<br>')}</p>" }.join("\n")
  end

  def pdf(title, body, values, footer:)
    text = merge(body, values)
    Prawn::Document.new(page_size: "LETTER", margin: [72, 72, 72, 72], info: { Title: title, Producer: "Writlog" }) do |pdf|
      pdf.font "Times-Roman"
      pdf.font_size 11.5
      text.split(/\n{2,}/).each_with_index do |para, i|
        if i.zero?
          pdf.text para, style: :bold, size: 13, align: :center
        else
          pdf.text para, leading: 2
        end
        pdf.move_down 10
      end
      pdf.number_pages "#{footer}  |  page <page> of <total>", at: [pdf.bounds.left, -20], size: 8, align: :center
    end.render
  end
end
