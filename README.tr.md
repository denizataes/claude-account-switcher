# Claude Code Hesap Seçici — Windows

Claude Code hesaplarını bildirim alanından değiştirin; beş saatlik ve haftalık kullanım limitlerini aynı panelde görün.

[Setup.exe indir](https://github.com/denizataes/claude-account-switcher/releases/latest/download/Claude-Hesap-Setup.exe) · [English documentation](README.md)

![Örnek hesaplarla tray paneli](docs/images/tray.png)
![Başlangıç, masaüstü kısayolu ve hemen açılma seçenekleri](docs/images/setup.png)
![Başlangıcı doğrulanmış örnek tamamlanma ekranı](docs/images/setup-complete.png)

Görüntüler demo hesap ve örnek kullanım verisidir; gerçek hesap bilgisi içermez.

1. Setup dosyasını çalıştırın. Yönetici yetkisi gerekmez; Windows başlangıcında açılma, masaüstü kısayolu ve kurulumdan sonra hemen başlatma seçeneklerini seçebilirsiniz. Güncellemeler mevcut kısayol tercihlerini korur.
2. Tray simgesinden **Mevcut hesabı kaydet** ile açık hesabı kaydedin veya **+ Yeni hesap** ile Claude'un normal tarayıcı girişini tamamlayın.
3. Bir hesap kartına tıklayın. Açık Claude oturumları varsa kapatma onayı gösterilir; kaydedilmemiş çalışma kesilebilir. Terminal pencereleri kapatılmaz.
4. Herhangi bir klasörden normal `claude` komutunu çalıştırın. `/status` ile hesabı kontrol edin.

Windows PowerShell 5.1, .NET Framework ve PATH üzerinde Claude Code gerekir. Uygulama arayüzü Türkçedir. Hesap sayısı sabit değildir; her ekip üyesi kendi bilgisayarında kendi hesaplarına girer. Yalnızca kurulum dosyasını paylaşın.

Hassas hesap kayıtları Windows kullanıcısına ait DPAPI ile şifrelenir. Hesap adlarını içeren index şifreli değildir. Kurulum/kaldırma hesap kayıtlarını ve mevcut Claude girişini korur. **Tokenları, credential dosyalarını veya accounts klasörünü GitHub'a yüklemeyin.**

Limit yüzdeleri hesap genelinde **kullanılan** miktarı gösterir. Dahili kullanım endpoint'i sürüme bağlıdır; veri en az beş dakika önbelleğe alınır, 429 durumunda beklenir, eski veri açıkça işaretlenir. Bilinmeyen değer sıfır gibi gösterilmez.

Araç bağımsızdır; resmi Anthropic uygulaması değildir. Claude Code'un dahili Windows oturum formatına bağlıdır; API-key/Console ve bulut sağlayıcısı girişleri desteklenmez. Setup dijital olarak imzalı değildir; Windows SmartScreen uyarı gösterebilir.

**1.6 kurulum:** paket önce doğrulanır; bilinen uygulama dosyaları, uygulamaya ait kısayollar ve Windows kaydı yedeklenir. Bildirilen kurulum hatalarında geri alınır; geri alma başarısızsa yedek konumu korunur. Hesap kayıtlarına dokunulmaz. Açık hesap işlemi varken güncelleme başlamaz. Gecikmiş kaldırma yardımcısı yeni kurulumu silemez. Ani sistem kapanmasından sonra kurulumu yeniden çalıştırmak gerekebilir.

Başlangıç artık VBS yerine doğrudan gizli Windows PowerShell kullanır. Uygulama başlangıcı doğrulanamazsa kurulum tamamlanmış olduğu açıkça belirtilir. `%LOCALAPPDATA%\ClaudeAccountSwitcher\setup.log` yalnızca aşama/durum ve zaman bilgisi içerir.

Sessiz kurulum: `Claude-Hesap-Setup.exe /install /quiet`. `/no-launch`, `/startup`, `/no-startup`, `/desktop`, `/no-desktop` seçenekleri desteklenir. Çıkış kodları: **0** başarılı veya başlatma istenmedi; **1** kurulum reddedildi/başarısız; **2** kuruldu, başlangıç doğrulanamadı. Sessiz mod diyalog açmaz.

Testler sahte kullanıcı dosyaları, kullanım verileri ve süreçler kullanır. Gerçek Claude hesabını değiştirmez veya gerçek oturumları kapatmaz. Performans ölçümleri cihaz ve masaüstü yüküne bağlıdır; her ortam için aynı hız veya sıfır hata garantisi verilmez.

Derleme, güvenlik sınırları, kullanım verisinin kaynağı ve testler için [English README](README.md) belgesine bakın.
