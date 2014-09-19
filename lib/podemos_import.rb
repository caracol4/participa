class PodemosImport
  # Importa los contenidos desde un CSV a la aplicación
  # La contraseña es el token enviado por SMS
  #
  # $ rails console staging
  # > require 'podemos_import'
  # > PodemosImport.init('/home/capistrano/juntos.csv')
  #
  # $ bundle exec rake environment resque:work QUEUE=* RAILS_ENV=staging 
  #
  #
  require 'csv'

  def self.convert_document_type(doc_type, doc_number)
    # doctypes: 
    # DNI = 1
    # NIE = 2
    # Pasaporte = 3
    ( doc_type == "Pasaporte" ) ? 3 : ( doc_number.starts_with?("Z", "X", "Y") ? 2 : 1 )
  end

  def self.invalid_record(u, row)
    error_email = {:email=>["Ya estas registrado con tu correo electrónico. Prueba a iniciar sesión o a pedir que te recordemos la contraseña.", "Ya estas registrado con tu correo electrónico. Prueba a iniciar sesión o a pedir que te recordemos la contraseña."]}
    error_document = {:email=>["Ya estas registrado con tu correo electrónico. Prueba a iniciar sesión o a pedir que te recordemos la contraseña.", "Ya estas registrado con tu correo electrónico. Prueba a iniciar sesión o a pedir que te recordemos la contraseña."]}
    logger_mail = Logger.new("#{Rails.root}/log/users_invalid_email.log")
    logger_doc = Logger.new("#{Rails.root}/log/users_invalid_document.log")
    logger_all = Logger.new("#{Rails.root}/log/users_invalid.log")
    case u.errors 
    when error_email 
      logger_mail.info row
    when error_document 
      logger_doc.info row
    else
      puts u.errors.messages
      puts row
      puts "*" * 10
      logger_all.info u.errors.messages
      logger_all.info row
    end
  end

  def self.process_row(row)
    now = DateTime.now
    u = User.new
    u.last_name = row[3][1]
    u.first_name = row[4][1]
    u.document_vatid = row[6][1] == "" ? row[7][1] : row[6][1]
    logger = Logger.new("#{Rails.root}/log/users_invalid.log")
    logger.info row[3][1]
    logger.info row[4]
    logger.info row[6]
    logger.info row[7]
    u.document_type = PodemosImport.convert_document_type(row[5][1], u.document_vatid)
    u.email = row[9][1]
    u.phone = row[10][1].sub('+','00')
    u.sms_confirmation_token = row[11][1]
    u.address = row[12][1]
    # legacy: un usuario puso una carta (literalmente)
    if row[13][1].length < 250 
      u.town = row[13][1]
    end
    u.postal_code = row[15][1]
    u.province = row[14][1] # TODO: convert to carmen
    u.country = row[16][1]  # TODO: convert to carmen
    # legacy: al principio no se preguntaba fecha de nacimiento
    unless row[8][1] == ""
      u.born_at = Date.parse row[8][1] # 1943-10-15 
    end
    # legacy: al principio no se preguntaba para recibir la newsletter
    if row[18][1] == 1
      u.wants_newsletter = true
    end
    u.password = row[11][1]
    u.password_confirmation = row[11][1]
    u.confirmed_at = now
    u.sms_confirmed_at = now
    #u.has_legacy_password = true
    u.save
    unless u.valid? 
      PodemosImport.invalid_record(u, row)
    end
  end

  def self.init csv_file
    CSV.foreach(csv_file, headers: true, encoding: 'windows-1251:utf-8') do |row|
      Resque.enqueue(PodemosImportWorker, row)
    end
  end

end
