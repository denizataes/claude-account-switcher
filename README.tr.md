# Claude Code Hesap Seçici — Windows

Claude Code hesaplarını bildirim alanından değiştirin; beş saatlik ve haftalık kullanım limitlerini aynı panelde görün.

[Setup.exe indir](https://github.com/denizataes/claude-account-switcher/releases/latest/download/Claude-Hesap-Setup.exe) · [English documentation](README.md)

1. Setup dosyasını çalıştırın. Yönetici yetkisi gerekmez; Windows başlangıcında açılmayı seçebilirsiniz.
2. Tray simgesinden **Mevcut hesabı kaydet** ile açık hesabı kaydedin veya **+ Yeni hesap** ile Claude'un normal tarayıcı girişini tamamlayın.
3. Bir hesap kartına tıklayın. Açık Claude oturumları varsa kapatma onayı gösterilir; kaydedilmemiş çalışma kesilebilir. Terminal pencereleri kapatılmaz.
4. Herhangi bir klasörden normal `claude` komutunu çalıştırın. `/status` ile hesabı kontrol edin.

Windows PowerShell 5.1, .NET Framework ve PATH üzerinde Claude Code gerekir. Uygulama arayüzü Türkçedir. Hesap sayısı sabit değildir; her ekip üyesi kendi bilgisayarında kendi hesaplarına girer. Yalnızca kurulum dosyasını paylaşın.

Hassas hesap kayıtları Windows kullanıcısına ait DPAPI ile şifrelenir. Hesap adlarını içeren index şifreli değildir. Kurulum/kaldırma hesap kayıtlarını ve mevcut Claude girişini korur. **Tokenları, credential dosyalarını veya accounts klasörünü GitHub'a yüklemeyin.**

Limit yüzdeleri hesap genelinde **kullanılan** miktarı gösterir. Dahili kullanım endpoint'i sürüme bağlıdır; veri en az beş dakika önbelleğe alınır, 429 durumunda beklenir, eski veri açıkça işaretlenir. Bilinmeyen değer sıfır gibi gösterilmez.

Araç bağımsızdır; resmi Anthropic uygulaması değildir. Claude Code'un dahili Windows oturum formatına bağlıdır; API-key/Console ve bulut sağlayıcısı girişleri desteklenmez. Setup dijital olarak imzalı değildir; Windows SmartScreen uyarı gösterebilir.

Derleme, güvenlik sınırları, kullanım verisinin kaynağı ve testler için [English README](README.md) belgesine bakın.
