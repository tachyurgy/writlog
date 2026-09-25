# Fictional data only. Every name, index number and amount below is invented.
# Idempotent: re-running leaves an already-seeded database alone.
if Matter.exists?
  puts "already seeded"
  return
end

T = {}
def template(key, version, name, description, body)
  T[[key, version]] = DocumentTemplate.find_or_create_by!(key:, version:) do |t|
    t.name = name
    t.description = description
    t.body = body.strip
  end
end

template "demand_letter", 1, "Demand for Payment (v1)", "Superseded first draft, kept so old documents still point at the text they were merged from.", <<~TXT
  DEMAND FOR PAYMENT

  {{as_of}}

  {{debtor_name}}
  {{debtor_address}}

  Re: {{client_name}} / {{matter_reference}}

  This office represents {{client_name}}. Our client's records show an unpaid balance of {{balance}}. Please remit payment or contact this office within ten days.
TXT

template "demand_letter", 2, "Demand for Payment", "Pre-suit demand with the cure period and a guarantor copy.", <<~TXT
  DEMAND FOR PAYMENT

  {{as_of}}

  {{debtor_name}}
  {{debtor_address}}

  Re: {{client_name}} / Our file {{matter_reference}}

  This office represents {{client_name}} in connection with amounts owed under its agreement with {{debtor_name}}. Our client's records reflect an original obligation of {{principal}}, payments to date of {{paid_to_date}}, and an unpaid balance of {{balance}}.

  Demand is hereby made for payment of {{balance}}. If you dispute this amount, or if you would like to discuss a resolution, including a payment arrangement, contact this office before the cure period ends. If we do not hear from you, our client has authorized us to commence an action in the Supreme Court of the State of New York, County of {{county}}, without further notice.

  A copy of this letter has been sent to {{guarantor_name}}, as guarantor.

  Counsel for {{client_name}}
TXT

template "restraining_notice", 1, "Restraining Notice to Garnishee (CPLR 5222)", "Post-judgment. Needs a judgment amount and entry date on the matter.", <<~TXT
  RESTRAINING NOTICE TO GARNISHEE

  SUPREME COURT OF THE STATE OF NEW YORK, COUNTY OF {{county}}
  {{client_name}}, Plaintiff, against {{debtor_name}}, Defendant.
  Index No. {{index_number}}

  WHEREAS, a judgment was entered on {{judgment_entered_on}} in the above action in favor of {{client_name}} and against {{debtor_name}} in the amount of {{judgment_amount}}, of which {{balance}} remains due and unpaid;

  TAKE NOTICE that pursuant to CPLR 5222(b), you are forbidden to make or suffer any sale, assignment or transfer of, or any interference with, any property in which the judgment debtor has an interest, except upon direction of the sheriff or pursuant to an order of the court, until the judgment is satisfied or vacated.

  This notice is effective for one year after service, as provided by CPLR 5222.

  Dated: {{as_of}}
  Attorneys for Judgment Creditor {{client_name}}
TXT

template "information_subpoena", 1, "Information Subpoena with Questions (CPLR 5224)", "Post-judgment discovery served with a restraining notice.", <<~TXT
  INFORMATION SUBPOENA

  SUPREME COURT OF THE STATE OF NEW YORK, COUNTY OF {{county}}
  {{client_name}} v. {{debtor_name}}, Index No. {{index_number}}

  THE PEOPLE OF THE STATE OF NEW YORK, TO THE RECIPIENT:

  WHEREAS, in the above action a judgment was entered on {{judgment_entered_on}} in the amount of {{judgment_amount}}, of which {{balance}} remains due and unpaid; NOW, THEREFORE, WE COMMAND YOU to answer in writing under oath, separately and fully, each question in the questionnaire accompanying this subpoena, and to return the answers together with the original questions within seven days after service.

  Dated: {{as_of}}
TXT

template "stipulation_of_settlement", 1, "Stipulation of Settlement", "Settlement terms stated against the current balance.", <<~TXT
  STIPULATION OF SETTLEMENT

  {{client_name}} and {{debtor_name}} (together with {{guarantor_name}}, as guarantor) agree to resolve matter {{matter_reference}} on the following terms.

  The parties acknowledge a balance of {{balance}} as of {{as_of}}, after payments of {{paid_to_date}}. Defendant shall pay the settlement amount in the installments set out in Schedule A. Upon default in any installment not cured within ten days of written notice, plaintiff may enter judgment for the full balance, less payments made.

  This stipulation may be signed in counterparts.
TXT

def open_matter(ref, client, debtor, address, guarantor, county, principal, opened_on)
  Matter.open!({ reference: ref, client_name: client, debtor_name: debtor, debtor_address: address,
                 guarantor_name: guarantor, county: }, principal_cents: principal, opened_on: Date.parse(opened_on), actor: "seed")
end

def ev(matter, kind, on, payload = {})
  Workflow.append!(matter, kind, effective_on: Date.parse(on), payload:, actor: "seed")
end

def comm(matter, at, channel, direction, who, subject, body = nil, doc = nil)
  Communication.log!(matter, channel:, direction:, counterparty: who, subject:, body:, occurred_at: Time.zone.parse(at), generated_document: doc)
end

def gen(matter, key, version = nil)
  t = version ? T[[key, version]] : DocumentTemplate.where(key:).order(version: :desc).first
  doc = DocumentRequest.call(matter.reload, t).document
  GenerateDocumentJob.perform_now(doc.id)
  doc.reload
end

clients = ["Harborline Merchant Funding LLC", "Pinecrest Capital Partners LLC", "Tidewater Equipment Finance Inc."]

# 1. Fresh intake
m = open_matter("WL-2026-1001", clients[0], "Blue Heron Bakery Corp.", "18 Linden Row, Hempstead, NY 11550", "Dana Okafor", "Nassau", 4_825_000, "2026-09-18")

# 2. Demand sent, cure period running
m = open_matter("WL-2026-1002", clients[1], "Saltmarsh Auto Body Inc.", "402 Quarry Road, Islip, NY 11751", "Victor Salas", "Suffolk", 7_150_000, "2026-09-02")
ev m, "demand_sent", "2026-09-15", { cure_days: 14 }
d = gen(m, "demand_letter")
comm m, "2026-09-15 10:12", "letter", "outbound", "Saltmarsh Auto Body Inc.", "Demand letter mailed (first class and certified)", nil, d
comm m, "2026-09-19 14:40", "phone", "inbound", "Victor Salas (guarantor)", "Guarantor called about a payment plan", "Asked for 6 monthly installments. Told him we would take it to the client."

# 3. Suit filed, service deadline running
m = open_matter("WL-2026-1003", clients[0], "Northfork Floral Design LLC", "7 Mill Pond Lane, Riverhead, NY 11901", "Priya Raman", "Suffolk", 3_310_000, "2026-07-06")
ev m, "demand_sent", "2026-07-08", { cure_days: 10 }
gen(m, "demand_letter", 1)
ev m, "suit_filed", "2026-08-03", { index_number: "608113/2026" }
comm m, "2026-08-03 16:05", "court_filing", "outbound", "Suffolk County Clerk (NYSCEF)", "Summons and verified complaint filed"

# 4. Served by deliver-and-mail: answer deadline computed from proof filing
m = open_matter("WL-2026-1004", clients[2], "Castle Point Deli & Grocery Corp.", "2210 Atlantic Ave, Brooklyn, NY 11233", "Omar Haddad", "Kings", 2_240_000, "2026-06-22")
ev m, "demand_sent", "2026-06-24"
ev m, "suit_filed", "2026-07-20", { index_number: "521907/2026" }
ev m, "served", "2026-08-28", { method: "substituted", proof_filed_on: "2026-09-01" }
comm m, "2026-09-01 11:30", "court_filing", "outbound", "Kings County Clerk (NYSCEF)", "Affidavit of service filed (CPLR 308(2))"

# 5. Served personally, answered, settled, paying
m = open_matter("WL-2026-1005", clients[1], "Greenport Marine Supply Inc.", "55 Front Street, Greenport, NY 11944", "Lena Brooks", "Suffolk", 9_600_000, "2026-03-02")
ev m, "demand_sent", "2026-03-04"
ev m, "suit_filed", "2026-03-30", { index_number: "604478/2026" }
ev m, "served", "2026-04-06", { method: "personal" }
ev m, "answer_received", "2026-04-24", { note: "General denial; counsel appeared" }
comm m, "2026-05-11 09:00", "email", "inbound", "Defense counsel", "Settlement proposal: $72,000 over 12 months"
ev m, "settlement_reached", "2026-05-20", { amount_cents: 7_200_000 }
gen(m, "stipulation_of_settlement")
ev m, "payment_received", "2026-06-20", { amount_cents: 600_000 }
ev m, "payment_received", "2026-07-20", { amount_cents: 600_000 }
ev m, "payment_received", "2026-08-20", { amount_cents: 600_000 }

# 6. Default, judgment, enforcement against the operating account
m = open_matter("WL-2026-1006", clients[0], "Five Towns Fitness Studio LLC", "311 Central Avenue, Lawrence, NY 11559", "Marco Bellini", "Nassau", 12_875_000, "2026-01-12")
ev m, "demand_sent", "2026-01-14"
ev m, "suit_filed", "2026-02-09", { index_number: "602231/2026" }
ev m, "served", "2026-02-18", { method: "secretary_of_state" }
ev m, "default_noted", "2026-03-25"
ev m, "judgment_entered", "2026-05-14", { amount_cents: 13_412_650 }
ev m, "restraining_notice_served", "2026-05-29", { recipient: "Example Community Bank, N.A." }
ev m, "information_subpoena_served", "2026-05-29", { recipient: "Example Community Bank, N.A." }
d = gen(m, "restraining_notice")
comm m, "2026-05-29 13:15", "letter", "outbound", "Example Community Bank, N.A.", "Restraining notice and information subpoena served", nil, d
comm m, "2026-06-12 10:02", "email", "inbound", "Example Community Bank, N.A. (legal processing)", "Account restrained: $18,406.22 held"
ev m, "execution_issued", "2026-06-18", { note: "Property execution delivered to the Nassau County Sheriff" }
ev m, "payment_received", "2026-07-30", { amount_cents: 1_840_622 }

# 7. Satisfied
m = open_matter("WL-2026-1007", clients[2], "Rockaway Print & Sign Co.", "90 Beach 116th Street, Queens, NY 11694", nil, "Queens", 1_990_000, "2026-02-02")
ev m, "demand_sent", "2026-02-04"
ev m, "suit_filed", "2026-03-02", { index_number: "709452/2026" }
ev m, "served", "2026-03-05", { method: "personal" }
ev m, "default_noted", "2026-04-01"
ev m, "judgment_entered", "2026-05-01", { amount_cents: 2_104_300 }
ev m, "payment_received", "2026-06-15", { amount_cents: 2_104_300 }
ev m, "satisfaction_filed", "2026-06-22"

# 8. Default noted, one-year default-judgment clock running
m = open_matter("WL-2026-1008", clients[1], "Merrick Road Pizzeria Inc.", "1450 Merrick Road, Merrick, NY 11566", "Sal Ventura", "Nassau", 2_780_000, "2026-05-04")
ev m, "demand_sent", "2026-05-06"
ev m, "suit_filed", "2026-06-01", { index_number: "605590/2026" }
ev m, "served", "2026-06-08", { method: "personal" }
ev m, "default_noted", "2026-07-06"

puts "seeded #{Matter.count} matters, #{MatterEvent.count} events, #{GeneratedDocument.count} documents, #{Communication.count} communications"
