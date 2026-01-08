require 'sinatra'
require 'mongo'
require 'json'
require 'fileutils'

set :bind, '0.0.0.0'
set :port, 3000

# --- CONFIGURACIÓN ---
PROJECT_ROOT = File.expand_path('..', __dir__) 
PUBLIC_DIR = File.join(PROJECT_ROOT, 'public')
UPLOADS_DIR = File.join(PUBLIC_DIR, 'uploads')
BACKUP_FILE = File.join(PROJECT_ROOT, 'backup_cursos.json')

FileUtils.mkdir_p(UPLOADS_DIR)
set :public_folder, PUBLIC_DIR

# --- MONGODB ---
# Aseguramos que la conexión esté lista
client = Mongo::Client.new('mongodb://mongodb:27017/plataforma_cursos')
cursos_col = client[:cursos]

# ==========================================
# 🔄 AUTO-RESTAURACIÓN AL INICIAR
# ==========================================
begin
  # Si la base de datos está vacía Y existe el backup...
  if cursos_col.count_documents == 0 && File.exist?(BACKUP_FILE)
    puts "⚠️ Base de datos vacía detectada. Iniciando restauración..."
    
    # Leemos el archivo JSON
    backup_data = JSON.parse(File.read(BACKUP_FILE))
    
    # Preparamos los datos para MongoDB
    cursos_para_insertar = backup_data.map do |curso|
      # Convertimos el ID de texto (String) vuelta a formato ID de Mongo (ObjectId)
      if curso['_id']
        curso['_id'] = BSON::ObjectId.from_string(curso['_id'])
      end
      # Convertimos las claves de String a Símbolos para que Ruby las entienda bien
      curso.transform_keys(&:to_sym)
    end

    # Insertamos todo de golpe
    if cursos_para_insertar.any?
      cursos_col.insert_many(cursos_para_insertar)
      puts "✅ ¡Restauración completada! Se han cargado #{cursos_para_insertar.count} cursos del backup."
    end
  end
rescue => e
  puts "❌ Error en la auto-restauración: #{e.message}"
end
# ==========================================

# --- VISTA PRINCIPAL ---
get '/' do
  cards_html = cursos_col.find.map do |curso|
    id = curso[:_id].to_s
    img_path = curso[:imagen] ? "/uploads/#{curso[:imagen]}" : "https://via.placeholder.com/400x250/e9ecef/adb5bd?text=Sin+Imagen"
    "
    <div class='col-md-4 mb-4'>
      <div class='card h-100 shadow-sm border-0'>
        <img src='#{img_path}' class='card-img-top rounded-top' style='height: 220px; object-fit: cover; background-color: #f0f0f0;'>
        <div class='card-body'>
          <h5 class='card-title fw-bold text-dark'>#{curso[:titulo]}</h5>
          <div class='mb-2'>
            <span class='badge bg-light text-dark border'>⏱️ #{curso[:duracion]}</span>
            <span class='badge bg-success bg-opacity-75'>🏷️ #{curso[:precio]}</span>
          </div>
        </div>
        <div class='card-footer bg-white border-top-0 d-flex justify-content-between py-3'>
          <a href='/editar/#{id}' class='btn btn-outline-primary btn-sm fw-bold px-3'>✏️ Editar</a>
          <form action='/borrar/#{id}' method='POST' style='margin:0;' onsubmit=\"return confirm('¿Borrar curso?');\">
            <button type='submit' class='btn btn-outline-danger btn-sm px-3'>🗑️ Borrar</button>
          </form>
        </div>
      </div>
    </div>
    "
  end.join

  layout(
    "
    <div class='p-5 mb-5 bg-dark text-white rounded-3 shadow-sm' style='background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);'>
      <div class='container-fluid py-2 text-center text-md-start'>
        <h1 class='display-4 fw-bold'>Mis Cursos Online</h1>
        <p class='fs-5 col-md-8'>Catálogo gestionado con Docker, Ruby y Git.</p>
        <a href='#form-crear' class='btn btn-light text-primary fw-bold btn-lg mt-3 shadow-sm'>+ Subir Nuevo Curso</a>
      </div>
    </div>
    <div class='container'><div class='row'>#{cards_html}</div></div>
    <div class='container mt-5 mb-5' id='form-crear' style='max-width: 700px;'>
      <div class='card shadow-lg border-0'>
        <div class='card-header bg-primary text-white py-3 fw-bold'>➕ Añadir Nuevo Curso</div>
        <div class='card-body p-4'>#{form_curso('/nuevo', 'Guardar Curso')}</div>
      </div>
    </div>
    "
  )
end

# --- GIT PUSH (INCLUYE DOCKER-COMPOSE) ---
post '/subir-git' do
  begin
    # 1. Crear Backup
    datos = cursos_col.find.to_a
    datos.each { |d| d[:_id] = d[:_id].to_s }
    File.write(BACKUP_FILE, JSON.pretty_generate(datos))

    # 2. Credenciales
    usuario = ENV['GITHUB_USER']
    token = ENV['GITHUB_TOKEN']
    
    if token.nil? || token.empty?
      return layout("<div class='alert alert-danger'>❌ Error: Faltan credenciales en docker-compose.yml</div>")
    end

    repo = "Docker_Ruby_MongoDB"
    remote_url = "https://#{usuario}:#{token}@github.com/#{usuario}/#{repo}.git"

    # 3. Comando Git (Sube TODO, incluido docker-compose)
    cmd = "cd #{PROJECT_ROOT} && " \
          "git init && " \
          "git config --global --add safe.directory /app && " \
          "git config --global user.email 'admin@cursos.com' && " \
          "git config --global user.name 'Web Admin' && " \
          "git remote remove origin 2>/dev/null || true && " \
          "git remote add origin #{remote_url} && " \
          "git branch -M main && " \
          "git add . && " \
          "git add -f backup_cursos.json && " \
          "(git commit -m 'Backup Auto' || true) && " \
          "git push -f origin main 2>&1"
    
    output = `#{cmd}`
    output_seguro = output.gsub(token, "******")

    if output.include?("error:") || output.include?("fatal:")
       layout("<div class='container mt-5 alert alert-danger shadow-sm'><h4>❌ Error</h4><pre>#{output_seguro}</pre><a href='/' class='btn btn-outline-danger'>Volver</a></div>")
    else
       layout("<div class='text-center mt-5 pt-5'><div style='font-size: 80px;'>✅</div><h1 class='text-success fw-bold'>Subida Correcta</h1><p class='lead'>Datos guardados y subidos a GitHub.</p><a href='/' class='btn btn-primary mt-3'>Volver</a></div>")
    end
  rescue => e
    layout("<div class='alert alert-danger'>Error Ruby: #{e.message}</div>")
  end
end

# --- AUXILIARES ---
def guardar_imagen(p); return nil unless p; fn="#{Time.now.to_i}_#{p[:filename]}"; File.open(File.join(UPLOADS_DIR, fn), 'wb'){|f| f.write(p[:tempfile].read)}; fn; end
post('/nuevo'){ n=guardar_imagen(params[:imagen]); cursos_col.insert_one({titulo: params[:titulo], duracion: params[:duracion], precio: params[:precio], imagen: n}); redirect '/'}
post('/actualizar/:id'){ id=BSON::ObjectId.from_string(params[:id]); d={titulo: params[:titulo], duracion: params[:duracion], precio: params[:precio]}; if params[:imagen]; n=guardar_imagen(params[:imagen]); d[:imagen]=n; end; cursos_col.update_one({_id: id}, {'$set'=>d}); redirect '/'}
post('/borrar/:id'){ cursos_col.delete_one(_id: BSON::ObjectId.from_string(params[:id])); redirect '/'}
get('/editar/:id'){ c=cursos_col.find(_id: BSON::ObjectId.from_string(params[:id])).first; layout("<div class='container mt-5' style='max-width:600px'><div class='card p-4'>#{form_curso("/actualizar/#{params[:id]}", 'Actualizar', c[:titulo], c[:duracion], c[:precio], true)}</div></div>")}
def layout(c); "<!DOCTYPE html><html lang='es'><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1'><title>Cursos</title><link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'><style>@import url('https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;600;700&display=swap'); body{font-family:'Poppins',sans-serif;background-color:#f8f9fa}</style></head><body><nav class='navbar navbar-expand-lg navbar-dark bg-dark py-3 shadow-sm'><div class='container'><a class='navbar-brand fw-bold fs-4' href='/'>📷 Cursos online</a><form action='/subir-git' method='POST' class='d-flex m-0'><button class='btn btn-outline-light fw-bold'>☁️ Push Git</button></form></div></nav>#{c}</body></html>"; end
def form_curso(a,b,t='',d='',p='',e=false); "<form action='#{a}' method='POST' enctype='multipart/form-data'><div class='mb-3'><label class='fw-bold'>Título</label><input type='text' name='titulo' value='#{t}' class='form-control' required></div><div class='row'><div class='col-6 mb-3'><label class='fw-bold'>Duración</label><input type='text' name='duracion' value='#{d}' class='form-control' required></div><div class='col-6 mb-3'><label class='fw-bold'>Precio</label><input type='text' name='precio' value='#{p}' class='form-control' required></div></div><div class='mb-3 bg-white p-2 border rounded'><label class='fw-bold'>Imagen</label><input type='file' name='imagen' class='form-control' accept='image/*'></div><button class='btn btn-primary w-100 fw-bold'>#{b}</button></form>"; end